#!/usr/bin/env python3
"""Neue Katalog-Keys (messages.newOne / newMany) in alle Web-Kataloge eintragen.

Die Wortwahl folgt der bereits übersetzten `messages.newMessage` derselben
Sprache. Sprachen, in denen Crowdin bislang englische Platzhalter führt
(新 = unübersetzt), erhalten konsequent denselben englischen Text – so wie
bei `overview.newMessages` und vielen anderen Keys.
"""
import json
from collections import OrderedDict
from pathlib import Path

# Sprache -> ("1 neue Nachricht", "{count} neue Nachrichten")
ONE = {
    "af": "1 nuwe boodskap", "ar": "رسالة جديدة واحدة", "ca": "1 missatge nou",
    "cs": "1 nová zpráva", "da": "1 ny besked", "de": "1 neue Nachricht",
    "el": "1 νέο μήνυμα", "en": "1 new message", "es": "1 mensaje nuevo",
    "fi": "1 uusi viesti", "fr": "1 nouveau message", "he": "הודעה חדשה אחת",
    "hu": "1 új üzenet", "it": "1 nuovo messaggio", "ja": "新規メッセージ1件",
    "ko": "새 메시지 1개", "nl": "1 nieuw bericht", "no": "1 ny melding",
    "pl": "1 nowa wiadomość", "pt": "1 nova mensagem", "ro": "1 mesaj nou",
    "ru": "1 новое сообщение", "sr": "1 nova poruka", "sv": "1 nytt meddelande",
    "tr": "1 yeni mesaj", "uk": "1 нове повідомлення", "vi": "1 tin nhắn mới",
    "zh": "1 条新消息",
}
MANY = {
    "af": "{count} nuwe boodskappe", "ar": "{count} رسالة جديدة", "ca": "{count} missatges nous",
    "cs": "{count} nových zpráv", "da": "{count} nye beskeder", "de": "{count} neue Nachrichten",
    "el": "{count} νέα μηνύματα", "en": "{count} new messages", "es": "{count} mensajes nuevos",
    "fi": "{count} uutta viestiä", "fr": "{count} nouveaux messages", "he": "{count} הודעות חדשות",
    "hu": "{count} új üzenet", "it": "{count} nuovi messaggi", "ja": "新規メッセージ{count}件",
    "ko": "새 메시지 {count}개", "nl": "{count} nieuwe berichten", "no": "{count} nye meldinger",
    "pl": "{count} nowych wiadomości", "pt": "{count} novas mensagens", "ro": "{count} mesaje noi",
    "ru": "{count} новых сообщений", "sr": "{count} novih poruka", "sv": "{count} nya meddelanden",
    "tr": "{count} yeni mesaj", "uk": "{count} нових повідомлень", "vi": "{count} tin nhắn mới",
    "zh": "{count} 条新消息",
}
# Sprachen ohne übersetzten Wortschatz (Crowdin-Platzhalter) -> englischer Text.
EN_ONLY = {"af", "ar", "ca", "he", "hu", "ko", "sr", "tr", "vi"}

root = Path(__file__).resolve().parent.parent / "messages"
for path in sorted(root.glob("*.json")):
    lang = path.stem
    one = "1 new message" if lang in EN_ONLY else ONE[lang]
    many = "{count} new messages" if lang in EN_ONLY else MANY[lang]
    data = json.loads(path.read_text(encoding="utf-8"), object_pairs_hook=OrderedDict)
    messages = data["messages"]
    for key, value in (("newOne", one), ("newMany", many)):
        messages[key] = value
    data["messages"] = OrderedDict(sorted(messages.items()))
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"{lang}: newOne={one!r} newMany={many!r}")