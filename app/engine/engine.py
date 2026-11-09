"""NextStep conversation engine: an explicit, channel-agnostic state machine.

    idle ─Hi─▶ consent ─agree─▶ age ─15–17/18–24─▶ menu
                  │               └─under 15─▶ exit (helpline, data deleted)
                  └─not now─▶ idle (nothing stored)
    menu ─▶ qa | check | loc (find a service) | lang
    check: q1…q6 ─▶ result ─▶ find / self-test / menu
    loc ─▶ service card ─▶ directions | another | remind ─(day 3, day 7)─▶ fu
    fu: yes | not yet | need help ─▶ barrier list
    ANY STATE: STOP, DELETE, MENU, HELP, crisis detector

Router order for free text (see docs/HANDOFF.md):
    1 global keywords → 2 crisis → 3 consent gate → 4 scope guardrails →
    5 state-specific → 6 answer bank → 7 fallback

`Engine.handle` is pure: it takes the stored state and one inbound event and
returns outbound messages, the new state (None = delete everything for this
user), aggregate events and side-effect actions. Channels apply the result.
"""
from __future__ import annotations

import copy as _copy
import logging
import re
from dataclasses import dataclass, field
from typing import Any

from ..copy_store import CopyStore
from ..llm.base import LLM, NoLLM
from ..retrieval.kb import KnowledgeBase
from ..services import ServiceFinder
from . import safety as S
from .checker import CheckScorer

log = logging.getLogger("app.engine")

# Button id -> copy ref used as its label.
BTN = {
    "consent_agree": ("consent", "btn_agree"), "consent_not_now": ("consent", "btn_not_now"), "consent_data": ("consent", "btn_data"),
    "age_15_17": ("age", "btn_15_17"), "age_18_24": ("age", "btn_18_24"), "age_under15": ("age", "btn_under15"),
    "lang_en": ("menu", "btn_en"), "lang_pcm": ("menu", "btn_pcm"),
    "qa_protect": ("qa", "btn_protect"), "qa_another": ("qa", "btn_another"), "qa_find": ("qa", "btn_find"),
    "menu": ("global", "btn_menu"),
    "check_start": ("check", "btn_start"), "check_not_now": ("check", "btn_not_now"),
    "check_find": ("check", "btn_find"), "check_selftest": ("check", "btn_selftest"),
    "ref_directions": ("referral", "btn_directions"), "ref_another": ("referral", "btn_another"), "ref_remind": ("referral", "btn_remind"),
    "ref_demo_loc": ("sim", "use_demo_location"), "sim_skip3": ("sim", "skip_3_days"), "say_hi": ("sim", "say_hi"),
    "fu_yes": ("followup", "btn_yes"), "fu_not_yet": ("followup", "btn_not_yet"), "fu_help": ("followup", "btn_help"),
    "fu_good": ("followup", "btn_good"), "fu_not_good": ("followup", "btn_not_good"), "fu_skip": ("followup", "btn_skip"),
    "fu_later": ("followup", "btn_later"), "fu_other": ("followup", "btn_other"),
    "crisis_call": ("crisis", "btn_call"), "crisis_safe": ("crisis", "btn_safe"),
    "cant_find": ("cant_help", "btn_find"), "cant_ask": ("cant_help", "btn_ask"),
}
ANS_BTN = {"y": "btn_yes", "n": "btn_no", "ns": "btn_not_sure", "rn": "btn_rather_not"}
for _i in range(1, 11):
    for _a, _k in ANS_BTN.items():
        BTN[f"chk_{_i}_{_a}"] = ("check", _k)
MENU_ROWS = [("menu_ask", "row_ask"), ("menu_check", "row_check"), ("menu_find", "row_find"), ("menu_lang", "row_lang")]
HELP_ROWS = [("fu_cost", "row_cost"), ("fu_scared", "row_scared"), ("fu_blocked", "row_blocked"), ("fu_other_text", "row_other")]
ALIASES = {"qa_find": "menu_find", "check_find": "menu_find", "cant_find": "menu_find", "cant_ask": "menu_ask",
           "qa_another": "menu_ask", "fu_other": "menu_find", "check_not_now": "menu"}

PIDGIN_HINTS = re.compile(r"\b(how far|abeg|wetin|una|dey|na wa|wahala|oya|sabi|pikin|abi|sef|wey)\b")
YES = {"yes", "y", "yeah", "yep", "ok", "okay", "i agree", "agree", "i gree", "gree", "sure", "yes o", "na so"}
NO = {"no", "n", "nope", "not now", "no be now", "later", "no thanks"}


@dataclass
class Inbound:
    kind: str                 # text | button | voice | location | followup_due
    text: str = ""            # free text, or the STT transcript for voice
    button: str = ""
    transcript_ok: bool = True
    followup_kind: str = ""   # day3 | day7 (followup_due only)


@dataclass
class Result:
    messages: list[dict] = field(default_factory=list)
    state: dict | None = None
    delete: bool = False
    events: list[tuple[str, str, str]] = field(default_factory=list)
    actions: list[dict] = field(default_factory=list)


def new_state(lang: str = "en") -> dict[str, Any]:
    return {"stage": "idle", "lang": lang, "tier": None, "consented": False, "q": 0, "score": 0,
            "sti": False, "safety": False, "svc_ids": [], "svc_idx": 0}


class Engine:
    def __init__(self, copy: CopyStore, kb: KnowledgeBase, scorer: CheckScorer, finder: ServiceFinder,
                 rules: S.SafetyRules, llm: LLM | None = None, *, demo_state: str = "Lagos",
                 compose_with_llm: bool = True, llm_crisis: bool = True, call_number: str = "",
                 demo_mode: bool = True):
        self.copy, self.kb, self.scorer, self.finder, self.rules = copy, kb, scorer, finder, rules
        self.llm = llm or NoLLM()
        self.demo_state = demo_state
        self.compose_with_llm = compose_with_llm
        self.llm_crisis = llm_crisis
        self.call_number = call_number
        self.demo_mode = demo_mode

    # ------------------------------------------------------------ helpers
    def m(self, ref=None, *, buttons=None, rows=None, kicker=None, safety=False, texts=None, kind="text",
          card=None, params=None, speak=False, draft=None, chunk=None) -> dict:
        msg: dict[str, Any] = {"kind": kind}
        if ref:
            msg["ref"] = list(ref)
        if params:
            msg["params"] = params
        if texts:
            msg["texts"] = texts
        if buttons:
            msg["buttons"] = [{"id": b, "ref": list(BTN[b])} for b in buttons]
        if rows:
            msg["list"] = rows
        if kicker:
            msg["kicker"] = kicker
        if card:
            msg["card"] = card
        if speak:
            msg["speak"] = True
        if chunk:
            msg["chunk"] = chunk
        msg["safety"] = bool(safety)
        msg["draft"] = self.copy.is_draft(ref) if (draft is None and ref) else bool(draft)
        return msg

    def sys(self, text: str = "", ref=None) -> dict:
        d = {"kind": "system", "safety": False, "draft": False}
        if ref:
            d["ref"] = list(ref)
        else:
            d["texts"] = {"en": text, "pcm": text}
        return d

    def menu_msg(self) -> dict:
        rows = [{"id": rid, "ref": ["menu", key], "desc_ref": ["menu", key + "_desc"]} for rid, key in MENU_ROWS]
        return self.m(("menu", "prompt"), rows=rows)

    def text_of(self, msg: dict, lang: str) -> str:
        """Plain text of a message in a language (used by channels and tests)."""
        if msg.get("texts"):
            return msg["texts"].get(lang) or msg["texts"].get("en") or ""
        if msg.get("ref"):
            return self.copy.t(msg["ref"], lang, **(msg.get("params") or {}))
        return ""

    def crisis(self, r: Result, st: dict, kind: str, source: str) -> None:
        if kind == "self_harm":
            r.messages.append(self.m(("crisis", "selfharm"), buttons=["crisis_call", "crisis_safe", "menu"], safety=True))
        else:
            r.messages.append(self.m(("crisis", "violence"), buttons=["crisis_call", "crisis_safe", "menu"], safety=True))
            if kind == "sexual_violence":
                r.messages.append(self.m(("crisis", "pep"), safety=True))
        r.events.append(("crisis_escalation", kind, source))

    # ------------------------------------------------------------ entry
    def handle(self, state: dict | None, inp: Inbound) -> Result:
        st = _copy.deepcopy(state) if state else new_state()
        r = Result()
        if inp.kind == "followup_due":
            self._followup_due(r, st, inp)
        elif inp.kind == "button":
            self._button(r, st, inp.button)
        elif inp.kind == "voice":
            self._voice(r, st, inp)
        elif inp.kind == "location":
            if st.get("consented") and st.get("tier"):
                st["stage"] = "loc"
                r.messages.append(self.m(("referral", "ask_location")))
            else:
                self._text(r, st, "hi", "text")
        else:
            self._text(r, st, inp.text, "text")
        if not r.delete:
            r.state = st
        return r

    # ------------------------------------------------------------ voice
    def _voice(self, r: Result, st: dict, inp: Inbound) -> None:
        if not st.get("consented") or not st.get("tier"):
            # Never process a voice note before consent; restart the consent flow.
            self._text(r, st, inp.text or "hi", "voice")
            return
        if not inp.transcript_ok or not inp.text.strip():
            r.messages.append(self.m(("extra", "voice_unavailable")))
            r.events.append(("voice_fallback", "stt", st["lang"]))
            return
        r.messages.append(self.m(("extra", "heard_tpl"), params={"transcript": inp.text.strip()[:300]}))
        self._text(r, st, inp.text, "voice")

    # ------------------------------------------------------------ text router
    def _text(self, r: Result, st: dict, text: str, input_kind: str) -> None:
        text = (text or "").strip()
        lang = st["lang"]
        kw = S.global_keyword(text)

        # 1. global keywords
        if kw == "stop":
            r.messages.append(self.m(("global", "stop")))
            r.delete = True
            r.actions.append({"type": "delete_user"})
            return
        if kw == "delete":
            r.messages.append(self.m(("global", "delete")))
            r.delete = True
            r.actions.append({"type": "delete_user"})
            r.events.append(("data_deleted", "", ""))
            return
        if kw == "help":
            self.crisis(r, st, "help_keyword", "keyword")
            return
        if kw == "menu":
            if st.get("consented") and st.get("tier"):
                st["stage"] = "menu"
                r.messages.append(self.menu_msg())
            else:
                self._start(r, st, text)
            return

        # 2. crisis detection – before everything else, in every state
        cr = self.rules.crisis_keywords(text)
        cls = None
        if cr.kind is None and self.llm_crisis and not isinstance(self.llm, NoLLM) and kw is None and len(text) > 3:
            cls = S.llm_classify(self.llm, text)
            if cls and cls.get("crisis") != "none":
                cr = S.CrisisResult(cls["crisis"], "llm")
        if cr.kind:
            self.crisis(r, st, cr.kind, cr.layer)
            if not st.get("consented"):
                r.delete = True  # nothing is stored for someone who has not consented
            return

        # 3. consent gate: nothing else happens before consent
        stage = st.get("stage", "idle")
        if not st.get("consented"):
            t = S.normalise(text).strip(" .!")
            if stage == "consent" and t in YES:
                self._button(r, st, "consent_agree")
            elif stage == "consent" and t in NO:
                self._button(r, st, "consent_not_now")
            elif stage == "consent":
                r.messages.append(self.m(("consent", "body"), buttons=["consent_agree", "consent_not_now", "consent_data"]))
            else:
                self._start(r, st, text)
            return
        if kw == "hi" and stage != "age":
            st["stage"] = "menu"
            r.messages.append(self.menu_msg())
            return

        # age must be known before any content
        if stage == "age" or not st.get("tier"):
            self._age_text(r, st, text)
            return

        # 4. scope guardrails
        scope = self.rules.scope_check(text)
        if scope is None and cls and cls.get("intent") in ("dose", "diagnosis", "injection", "offtopic"):
            scope = cls["intent"]
        if scope:
            self._out_of_scope(r, st, scope)
            return

        # 5. state-specific
        if stage == "loc":
            self._find(r, st, text)
            return
        if stage == "check":
            t = S.normalise(text).strip(" .!")
            ans = {"yes": "y", "y": "y", "no": "n", "n": "n", "not sure": "ns", "i no sure": "ns",
                   "rather not say": "rn", "i no wan talk": "rn", "skip": "rn"}.get(t)
            qi = st.get("q", 0)
            if ans and qi and ans in self.scorer.answers_for(qi):
                self._check_answer(r, st, qi, ans)
            else:
                self._ask_q(r, st, qi or 1)
            return

        # 6. answer bank
        if self._answer(r, st, text, input_kind):
            return
        words = len(S.normalise(text).split())
        if stage == "qa" or words >= 3 or input_kind == "voice":
            r.messages.append(self.m(("qa", "unknown"), buttons=["qa_find", "menu"]))
            r.events.append(("question_asked", "unknown", input_kind))
            return

        # 7. fallback
        r.messages.append(self.m(("global", "fallback"), buttons=["menu"]))

    def _start(self, r: Result, st: dict, text: str) -> None:
        lang = "pcm" if PIDGIN_HINTS.search(S.normalise(text or "")) else st.get("lang", "en")
        st.clear()
        st.update(new_state(lang))
        st["stage"] = "consent"
        r.messages.append(self.m(("consent", "intro")))
        r.messages.append(self.m(("consent", "body"), buttons=["consent_agree", "consent_not_now", "consent_data"]))

    def _age_text(self, r: Result, st: dict, text: str) -> None:
        t = S.normalise(text)
        if re.search(r"under\s*15|below\s*15|less than 15", t):
            self._button(r, st, "age_under15")
            return
        m = re.search(r"\b(\d{1,2})\b", t)
        if m:
            age = int(m.group(1))
            if age < 15:
                self._button(r, st, "age_under15")
            elif age <= 17:
                self._button(r, st, "age_15_17")
            elif age <= 24:
                self._button(r, st, "age_18_24")
            else:
                st.update(stage="menu", tier="over_24")
                r.events.append(("age_tier_selected", "over_24", ""))
                r.messages.append(self.m(("age", "over24")))
            return
        st["stage"] = "age"
        r.messages.append(self.m(("age", "ask"), buttons=["age_15_17", "age_18_24", "age_under15"]))

    def _out_of_scope(self, r: Result, st: dict, kind: str) -> None:
        if kind == "dose":
            r.messages.append(self.m(("cant_help", "dose"), buttons=["cant_find", "cant_ask", "menu"]))
        elif kind == "diagnosis":
            r.messages.append(self.m(("extra", "diagnosis"), buttons=["cant_find", "menu"]))
        elif kind == "injection":
            r.messages.append(self.m(("extra", "injection"), buttons=["cant_ask", "menu"]))
        else:
            r.messages.append(self.m(("cant_help", "offtopic"), buttons=["cant_ask", "menu"]))
        r.events.append(("out_of_scope", kind, ""))

    # ------------------------------------------------------------ stateless Q&A (app API)
    def detect_crisis(self, text: str) -> tuple[str | None, str, dict | None]:
        """Layer (a) keywords, then layer (b) LLM classifier if configured."""
        cr = self.rules.crisis_keywords(text)
        if cr.kind:
            return cr.kind, "keyword", None
        cls = None
        if self.llm_crisis and not isinstance(self.llm, NoLLM) and len(text.strip()) > 3:
            cls = S.llm_classify(self.llm, text)
            if cls and cls.get("crisis") not in (None, "none"):
                return cls["crisis"], "llm", cls
        return None, "", cls

    def crisis_payload(self, kind: str, lang: str) -> dict:
        refs = [["crisis", "selfharm"]] if kind == "self_harm" else [["crisis", "violence"]]
        if kind == "sexual_violence":
            refs.append(["crisis", "pep"])
        return {"type": "crisis", "crisis": kind, "refs": refs,
                "text": "\n\n".join(self.copy.t(r, lang) for r in refs), "draft": True}

    def ask(self, question: str, lang: str, tier: str | None, input_kind: str = "text") -> tuple[dict, list[tuple]]:
        """Crisis → scope → grounded answer bank. Returns (response, events). Nothing is stored."""
        q = (question or "").strip()[:1000]
        events: list[tuple] = []
        kind, layer, cls = self.detect_crisis(q)
        if kind:
            events.append(("crisis_escalation", kind, layer))
            return self.crisis_payload(kind, lang), events
        scope = self.rules.scope_check(q)
        if scope is None and cls and cls.get("intent") in ("dose", "diagnosis", "injection", "offtopic"):
            scope = cls["intent"]
        if scope:
            ref = {"dose": ["cant_help", "dose"], "diagnosis": ["extra", "diagnosis"],
                   "injection": ["extra", "injection"]}.get(scope, ["cant_help", "offtopic"])
            events.append(("out_of_scope", scope, ""))
            return {"type": "out_of_scope", "scope": scope, "ref": ref, "text": self.copy.t(ref, lang),
                    "draft": self.copy.is_draft(ref)}, events
        tier_f = tier if tier in ("15_17", "18_24") else None
        hits = self.kb.search(q, lang, tier_f)
        if not hits:
            events.append(("question_asked", "unknown", input_kind))
            return {"type": "unknown", "ref": ["qa", "unknown"], "text": self.copy.t(("qa", "unknown"), lang),
                    "draft": True}, events
        top = hits[0].chunk
        text = (self.kb.get(top.id, lang) or top).body
        used = [top.id]
        composed_by = "verbatim"
        if self.compose_with_llm and not isinstance(self.llm, NoLLM):
            composed, used_ids = S.compose_answer(self.llm, q, [h.chunk for h in hits], lang)
            if composed and S.post_check(composed, "\n".join(h.chunk.body for h in hits)) is None:
                text, used, composed_by = composed, used_ids, "llm"
            elif composed:
                log.warning("post-generation check blocked a composed answer")
        sources = []
        for cid in used:
            c = self.kb.get(cid, lang)
            if c:
                sources.append({"chunk_id": c.id, "source_document": c.source_document,
                                "source_section": c.source_section, "review_status": c.review_status})
        events.append(("question_asked", (top.topic or "general")[:32], input_kind))
        return {"type": "answer", "text": text, "sources": sources, "composed_by": composed_by,
                "draft": not top.is_approved, "topic": top.topic}, events

    # ------------------------------------------------------------ answer bank
    def _answer(self, r: Result, st: dict, question: str, input_kind: str) -> bool:
        lang = st["lang"]
        tier = st.get("tier") if st.get("tier") in ("15_17", "18_24") else None
        hits = self.kb.search(question, lang, tier)
        if not hits:
            return False
        top = hits[0].chunk
        texts = {}
        for L in ("en", "pcm"):
            c = self.kb.get(top.id, L)
            if c:
                texts[L] = c.body
        used = [top.id]
        if self.compose_with_llm and not isinstance(self.llm, NoLLM):
            composed, used_ids = S.compose_answer(self.llm, question, [h.chunk for h in hits], lang)
            if composed:
                reason = S.post_check(composed, "\n".join(h.chunk.body for h in hits))
                if reason is None:
                    texts = {lang: composed}
                    used = used_ids
                else:
                    log.warning("post-generation check blocked composed answer: %s", reason)
        buttons = [b for b in top.buttons if b in BTN][:3] or ["qa_another", "menu"]
        r.messages.append(self.m(kind="text", texts=texts, buttons=buttons, speak=True,
                                 draft=not top.is_approved, chunk={"ids": used, "source": top.source_document,
                                                                  "section": top.source_section, "status": top.review_status}))
        st["stage"] = "qa"
        r.events.append(("question_asked", (top.topic or "general")[:32], input_kind))
        return True

    # ------------------------------------------------------------ buttons
    def _button(self, r: Result, st: dict, b: str) -> None:
        b = ALIASES.get(b, b)
        consented = st.get("consented")

        if b == "say_hi":
            self._start(r, st, "hi")
            return
        if b.startswith("consent_"):
            if b == "consent_agree":
                st.update(consented=True, stage="age")
                r.events.append(("conversation_started", st["lang"], ""))
                r.messages.append(self.m(("consent", "agreed")))
                r.messages.append(self.m(("age", "ask"), buttons=["age_15_17", "age_18_24", "age_under15"]))
            elif b == "consent_not_now":
                r.messages.append(self.m(("consent", "not_now"), buttons=["say_hi"]))
                r.delete = True
            else:
                st["stage"] = "consent"
                r.messages.append(self.m(("consent", "data"), buttons=["consent_agree", "consent_not_now"]))
            return
        if b in ("crisis_call", "crisis_safe"):
            if b == "crisis_safe":
                r.messages.append(self.m(("crisis", "safe_now"), buttons=["menu"], safety=True))
            elif self.call_number:
                r.messages.append({"kind": "call", "number": self.call_number, "ref": ["crisis", "btn_call"], "safety": True, "draft": False})
            else:
                r.messages.append(self.sys("Demo: would call " + self.copy.fill("[VERIFIED HELPLINE 1]")))
            return
        if not consented:
            self._start(r, st, "hi")
            return
        if b.startswith("age_"):
            if b == "age_under15":
                r.messages.append(self.m(("age", "under15"), buttons=["say_hi"], safety=True))
                r.events.append(("age_tier_selected", "under_15", ""))
                r.delete = True
                return
            tier = "15_17" if b == "age_15_17" else "18_24"
            st.update(tier=tier, stage="menu")
            r.events.append(("age_tier_selected", tier, ""))
            r.messages.append(self.m(("age", "teen" if tier == "15_17" else "adult")))
            r.messages.append(self.menu_msg())
            return
        if not st.get("tier"):
            self._age_text(r, st, "")
            return

        if b == "menu":
            st["stage"] = "menu"
            r.messages.append(self.menu_msg())
        elif b == "menu_ask":
            st["stage"] = "qa"
            r.messages.append(self.m(("qa", "prompt")))
        elif b == "qa_protect":
            c = self.kb.get("prevention-overview", st["lang"])
            if c:
                texts = {L: (self.kb.get("prevention-overview", L) or c).body for L in ("en", "pcm")}
                r.messages.append(self.m(texts=texts, buttons=["qa_find", "qa_another"], speak=True, draft=not c.is_approved,
                                         chunk={"ids": [c.id], "source": c.source_document, "section": c.source_section, "status": c.review_status}))
                r.events.append(("question_asked", "prevention", "button"))
            else:
                r.messages.append(self.m(("qa", "unknown"), buttons=["qa_find", "menu"]))
        elif b == "menu_check":
            r.messages.append(self.m(("check", "intro"), buttons=["check_start", "check_not_now"]))
        elif b == "check_start":
            st.update(stage="check", q=0, score=0, sti=False, safety=False)
            r.events.append(("check_started", "", ""))
            self._ask_q(r, st, 1)
        elif b.startswith("chk_"):
            _, qi, ans = b.split("_", 2)
            if st.get("stage") == "check" and int(qi) == st.get("q"):
                self._check_answer(r, st, int(qi), ans)
            else:
                r.messages.append(self.m(("global", "fallback"), buttons=["menu"]))
        elif b == "check_selftest":
            r.messages.append(self.m(("check", "selftest"), buttons=["check_find", "menu"]))
        elif b == "menu_find":
            st["stage"] = "loc"
            r.messages.append(self.m(("referral", "ask_location"), buttons=["ref_demo_loc"] if self.demo_mode else None))
        elif b == "ref_demo_loc":
            self._find(r, st, "Yaba, Lagos", demo=True)
        elif b == "ref_another":
            ids, idx = st.get("svc_ids") or [], st.get("svc_idx", 0) + 1
            if idx < len(ids):
                st["svc_idx"] = idx
                self._card(r, st, ids[idx])
            else:
                r.messages.append(self.m(("extra", "referral_no_more"), buttons=["menu"]))
        elif b == "ref_directions":
            ids = st.get("svc_ids") or []
            svc = self.finder.by_id(ids[st.get("svc_idx", 0)]) if ids else None
            if svc and svc.verified and svc.maps_url:
                r.messages.append({"kind": "url", "url": svc.maps_url, "ref": ["referral", "btn_directions"], "safety": False, "draft": False})
            else:
                r.messages.append(self.sys("Demo: would open directions in Maps"))
        elif b == "ref_remind":
            r.actions.append({"type": "schedule_followups", "lang": st["lang"], "tier": st.get("tier")})
            r.events.append(("reminder_opt_in", "", ""))
            r.messages.append(self.m(("referral", "remind_ok"), buttons=["sim_skip3"] if self.demo_mode else None))
        elif b == "sim_skip3":
            r.actions.append({"type": "simulate_followup"})
        elif b in ("fu_yes", "fu_not_yet", "fu_help", "fu_later", "fu_good", "fu_not_good", "fu_skip",
                   "fu_cost", "fu_scared", "fu_blocked", "fu_other_text"):
            self._followup_button(r, st, b)
        elif b == "menu_lang":
            r.messages.append(self.m(("menu", "lang_prompt"), buttons=["lang_en", "lang_pcm"]))
        elif b in ("lang_en", "lang_pcm"):
            st["lang"] = "en" if b == "lang_en" else "pcm"
            st["stage"] = "menu"
            r.messages.append(self.m(("menu", "lang_set")))
            r.messages.append(self.menu_msg())
        else:
            r.messages.append(self.m(("global", "fallback"), buttons=["menu"]))

    # ------------------------------------------------------------ private check
    def _ask_q(self, r: Result, st: dict, i: int) -> None:
        st["q"] = i
        btns = [f"chk_{i}_{a}" for a in self.scorer.answers_for(i)]
        r.messages.append(self.m(("check", f"q{i}"), buttons=btns, kicker=i))

    def _check_answer(self, r: Result, st: dict, i: int, ans: str) -> None:
        qid = f"q{i}"
        st["score"] = st.get("score", 0) + self.scorer.points(qid, ans)
        if self.scorer.flag("sti_signs", qid, ans):
            st["sti"] = True
        if self.scorer.flag("safeguarding", qid, ans):
            st["safety"] = True
            r.messages.append(self.m(("check", "q5_yes"), safety=True))
        if i < self.scorer.n:
            self._ask_q(r, st, i + 1)
            return
        band = self.scorer.band(st["score"])
        if st.get("sti"):
            r.messages.append(self.m(("check", "result_sti")))
        r.messages.append(self.m(("check", "result_next" if band == "next" else "result_low"),
                                 buttons=["check_find", "check_selftest", "menu"]))
        r.events.append(("check_completed", band, ""))
        if st.get("safety"):
            self.crisis(r, st, "sexual_violence", "check_q5")
        # Answers and score are cleared as soon as the result is shown.
        st.update(stage="menu", q=0, score=0, sti=False, safety=False)

    # ------------------------------------------------------------ referral
    def _find(self, r: Result, st: dict, area: str, demo: bool = False) -> None:
        tier = st.get("tier")
        found = self.finder.demo_default(tier) if demo else self.finder.find(area, tier)
        if not found:
            r.messages.append(self.m(("extra", "referral_none"), buttons=["menu"]))
            return
        st.update(svc_ids=[s.id for s in found], svc_idx=0, stage="menu")
        r.messages.append(self.m(("referral", "intro")))
        self._card(r, st, found[0].id)
        state_slug = re.sub(r"[^a-z0-9_-]", "", found[0].state.lower())[:32] or "unknown"
        r.events.append(("referral_given", state_slug, "verified" if found[0].verified else "demo"))

    def _card(self, r: Result, st: dict, sid: str) -> None:
        s = self.finder.by_id(sid)
        if not s:
            return
        card = {
            "id": s.id, "name": s.name, "address": f"{s.address}, {s.area}", "hours_raw": f"{s.days}, {s.hours}",
            "verified": s.verified, "is_free": s.is_free, "youth_friendly": s.youth_friendly,
            "demo_tag_ref": None if s.verified else ["extra", "referral_demo_tag"],
        }
        r.messages.append(self.m(("referral", "expect"), kind="card", card=card,
                                 buttons=["ref_directions", "ref_another", "ref_remind"]))
        # The channel turns this into a short referral code shown on the card (clinics confirm it).
        r.actions.append({"type": "referral", "service_id": s.id, "state": s.state, "lang": st["lang"], "tier": st.get("tier") or ""})

    # ------------------------------------------------------------ follow-up
    def _followup_due(self, r: Result, st: dict, inp: Inbound) -> None:
        st.update(consented=True, stage="fu")
        r.messages.append(self.sys(ref=("followup", "time_label")))
        r.messages.append(self.m(("followup", "ping")))
        r.messages.append(self.m(("followup", "ask"), buttons=["fu_yes", "fu_not_yet", "fu_help"]))

    def _followup_button(self, r: Result, st: dict, b: str) -> None:
        if b == "fu_yes":
            r.events.append(("visit_confirmed", "", ""))
            r.actions.append({"type": "cancel_followups"})
            r.messages.append(self.m(("followup", "yes"), buttons=["fu_good", "fu_not_good", "fu_skip"]))
        elif b == "fu_not_yet":
            r.events.append(("visit_not_yet", "", ""))
            r.messages.append(self.m(("followup", "not_yet"), buttons=["fu_later", "fu_other", "menu"]))
        elif b == "fu_later":
            r.actions.append({"type": "ensure_followup", "lang": st["lang"], "tier": st.get("tier")})
            r.messages.append(self.m(("extra", "fu_later_ok"), buttons=["menu"]))
        elif b == "fu_help":
            r.events.append(("followup_help", "", ""))
            rows = [{"id": rid, "ref": ["followup", key], "desc_ref": ["followup", key + "_desc"]} for rid, key in HELP_ROWS]
            r.messages.append(self.m(("followup", "help"), rows=rows))
        elif b in ("fu_good", "fu_not_good", "fu_skip"):
            st["stage"] = "menu"
            r.messages.append(self.m(("extra", "fu_rated"), buttons=["menu"]))
        elif b == "fu_cost":
            r.events.append(("barrier_reported", "cost", ""))
            r.messages.append(self.m(("followup", "help_cost"), buttons=["fu_other", "menu"]))
        elif b == "fu_scared":
            r.events.append(("barrier_reported", "scared", ""))
            r.messages.append(self.m(("followup", "help_scared"), buttons=["qa_find", "menu"]))
        elif b == "fu_blocked":
            r.events.append(("barrier_reported", "blocked", ""))
            r.messages.append(self.m(("followup", "help_blocked"), safety=True))
            self.crisis(r, st, "violence", "followup_blocked")
        elif b == "fu_other_text":
            r.events.append(("barrier_reported", "other", ""))
            st["stage"] = "qa"
            r.messages.append(self.m(("qa", "prompt")))
