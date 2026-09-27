"""Offline tests for the gettext-aware Jinja markup extension."""

import io
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from jinja2 import Environment

import localization
from localization import (
    TemplateTextTranslationExtension,
    _l10n_markup,
    extract_template_messages,
)


class LocalizationTests(unittest.TestCase):
    def render(self, template, translations=None, **context):
        translations = translations or {}
        seen = []

        def translate(message):
            seen.append(message)
            return translations.get(message, message)

        original = localization.translate_static
        localization.translate_static = translate
        try:
            env = Environment(extensions=[TemplateTextTranslationExtension], autoescape=True)
            env.globals["_l10n_markup"] = _l10n_markup
            rendered = env.from_string(template).render(**context)
        finally:
            localization.translate_static = original
        return rendered, seen

    def test_translates_static_text_and_accessibility_attributes(self):
        rendered, seen = self.render(
            '<p>Hallo &amp; willkommen</p><input placeholder="Suchen &amp; finden">',
            {"Hallo & willkommen": "Hello & welcome",
             "Suchen & finden": "Search & find"},
        )
        self.assertEqual(
            rendered,
            '<p>Hello &amp; welcome</p><input placeholder="Search &amp; find">',
        )
        self.assertIn("Hallo & willkommen", seen)
        self.assertIn("Suchen & finden", seen)

    def test_jinja_values_are_not_sent_to_translator(self):
        rendered, seen = self.render(
            "<p>Klasse {{ school_class }}</p><p>{{ provider_text }}</p>",
            {"Klasse": "Class"},
            school_class="7 & 8",
            provider_text="Muster & Söhne",
        )
        self.assertEqual(
            rendered,
            "<p>Class 7 &amp; 8</p><p>Muster &amp; Söhne</p>",
        )
        self.assertNotIn("Muster & Söhne", seen)
        self.assertNotIn("7 & 8", seen)

    def test_dynamic_attributes_and_raw_elements_are_untouched(self):
        rendered, seen = self.render(
            '<input title="{{ account_name }}">'
            '<script>const label = "Bitte";</script>'
            '<style>.notice { content: "Bitte"; }</style><p>Bitte</p>',
            {"Bitte": "Please"},
            account_name="Schule & Co.",
        )
        self.assertIn('title="Schule &amp; Co."', rendered)
        self.assertIn('const label = "Bitte";', rendered)
        self.assertIn('content: "Bitte"', rendered)
        self.assertTrue(rendered.endswith("<p>Please</p>"))
        self.assertEqual(seen.count("Bitte"), 1)

    def test_extractor_collects_static_copy_only(self):
        source = (
            "<p>Willkommen</p>\n"
            "<!-- Kommentar -->\n"
            "<script>gettext('JS-Text')</script>\n"
            "<p>{{ school_name }}</p>\n"
            "<input aria-label=\"Profil öffnen\">\n"
            "{{ gettext('Markierte Meldung') }}\n"
        )
        extracted = list(extract_template_messages(
            io.StringIO(source), {"gettext": None}, (), {"encoding": "utf-8"},
        ))
        messages = [item[2] for item in extracted]
        self.assertIn("Willkommen", messages)
        self.assertIn("Profil öffnen", messages)
        self.assertIn("Markierte Meldung", messages)
        self.assertNotIn("JS-Text", messages)
        self.assertNotIn("school_name", messages)


if __name__ == "__main__":
    unittest.main()
