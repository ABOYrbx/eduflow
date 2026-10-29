#!/usr/bin/env python3
"""macOS-Katalog: Anzeige-Labels fuer `Recipient.kind` ergaenzen.

`kind` ist ein stabiler englischer API-Wert ("teacher"/"student") und wird
nicht uebersetzt; die View zeigte bisher den Rohwert an (deutsches "Lehrer"
im Echtmodus). Diese beiden Keys tragen die Anzeige.

`sourceLanguage` ist "en"; beide Keys bekommen deshalb in allen bereits im
Katalog vorhandenen Sprachen einen Eintrag.
"""
import json
from pathlib import Path

LABELS = {
    "messages_role_teacher": {
        "comment": "Messages: recipient role teacher",
        "en": "Teacher", "de": "Lehrer", "af": "Onderwyser", "ar": "معلّم",
        "ca": "Docent", "cs": "Učitel", "da": "Lærer", "el": "Δάσκαλος",
        "es": "Profesor", "fi": "Opettaja", "fr": "Enseignant", "he": "מורה",
        "hu": "Tanár", "it": "Insegnante", "ja": "担任教師", "ko": "교사",
        "nl": "Docent", "no": "Lærer", "pl": "Nauczyciel", "pt": "Professor",
        "pt-BR": "Professor", "ro": "Profesor", "ru": "Учитель",
        "sr": "Наставник", "sv": "Lärare", "tr": "Öğretmen",
        "uk": "Вчитель", "vi": "Giáo viên", "zh-Hans": "教师",
        "zh-Hant": "教師",
    },
    "messages_role_student": {
        "comment": "Messages: recipient role student",
        "en": "Student", "de": "Schüler", "af": "Leerling", "ar": "طالب",
        "ca": "Alumne", "cs": "Žák", "da": "Elev", "el": "Μαθητής",
        "es": "Alumno", "fi": "Oppilas", "fr": "Élève", "he": "תלמיד",
        "hu": "Diák", "it": "Studente", "ja": "生徒", "ko": "학생",
        "nl": "Leerling", "no": "Elev", "pl": "Uczeń", "pt": "Aluno",
        "pt-BR": "Aluno", "ro": "Elev", "ru": "Ученик",
        "sr": "Ученик", "sv": "Elev", "tr": "Öğrenci",
        "uk": "Учень", "vi": "Học sinh", "zh-Hans": "学生",
        "zh-Hant": "學生",
    },
}

path = Path(__file__).resolve().parent.parent / "EduFlow" / "Resources" / "Localizable.xcstrings"
data = json.loads(path.read_text(encoding="utf-8"))
assert data.get("sourceLanguage") == "en", "sourceLanguage muss en sein"

vorhanden = set(data["strings"])
for key, sprachen in LABELS.items():
    assert key not in vorhanden, f"{key} existiert bereits"
    data["strings"][key] = {
        "comment": sprachen["comment"],
        "localizations": {
            code: {"stringUnit": {"state": "translated", "value": text}}
            for code, text in sprachen.items() if code != "comment"
        },
    }
    print(f"{key}: {len(data['strings'][key]['localizations'])} Sprachen")

path.write_text(json.dumps(data, ensure_ascii=False, indent=2, separators=(",", " : ")) + "\n", encoding="utf-8")
print("Katalog geschrieben")