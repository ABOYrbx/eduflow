"""Wochen-Essensplan der Mensa (SWS-Schulen-PDF).

Lädt das PDF der aktuellen Kalenderwoche von der SWS-Website, z. B.
`.../wp-content/uploads/2026/09/Mensa-und-Ausser-Haus-39.-KW.pdf`
(KW + Upload-Monat im Pfad), parst daraus die Tagesgerichte (Mo–Fr)
und cached das Ergebnis wochenweise unter `.cache/essen_YYYY-Www.json`.

Alles best-effort wie in `cache.py`: kein Treffer/offline -> alter Stand
falls vorhanden, sonst Fehlermeldung statt 500. Der Plan ist öffentlich
(schulweit, nicht pro User), daher liegt der Cache global ohne User-Hash.
"""

import json
import os
import re
import tempfile
from datetime import date, datetime, timedelta
from io import BytesIO
from pathlib import Path

import requests

BASE_DIR = Path(__file__).resolve().parent
CACHE_DIR = BASE_DIR / ".cache"

# PDF-Quelle (bei Bedarf per Env auf andere Schule zeigen).
ESSEN_BASE_URL = os.environ.get("ESSEN_BASE_URL", "https://www.sws-schulen.de").rstrip("/")
# Wochenplan ändert sich selten: 6 Stunden frisch, danach neu laden.
ESSEN_TTL_S = int(os.environ.get("EDUFLOW_ESSEN_TTL", "21600"))

DAY_NAMES = ["Montag", "Dienstag", "Mittwoch", "Donnerstag", "Freitag"]

_DAY_RE = re.compile(
    r"(Montag|Dienstag|Mittwoch|Donnerstag|Freitag|Samstag|Sonnabend|Sonntag)\s*:")
_PRICE_RE = re.compile(r"(\d{1,3},\d{2})\s*€")
_HEADER_RE = re.compile(
    r"Speisekarte\s+Montag\s+(\d{1,2})\.(\d{1,2})\.?\s*bis\s*"
    r"Freitag\s+(\d{1,2})\.(\d{1,2})\.(\d{4})")

_DATETIME_FMT = "%Y-%m-%d %H:%M:%S"


class EssenUnavailable(RuntimeError):
    """Essenplan gerade nicht lieferbar (Netz, Quelle oder PDF-Tool)."""


# ------------------------------------------------------------ Cache-Helpers

def _cache_path(week_key: str) -> Path:
    return CACHE_DIR / f"essen_{week_key}.json"


def _read_json(path: Path):
    try:
        with open(path, "r", encoding="utf-8") as f:
            data = json.load(f)
        return data if isinstance(data, dict) else None
    except Exception:
        return None


def _atomic_write_json(path: Path, payload: dict) -> None:
    try:
        CACHE_DIR.mkdir(parents=True, exist_ok=True)
    except Exception:
        pass
    fd, tmp = tempfile.mkstemp(prefix=path.name + ".", dir=str(path.parent))
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(payload, f, ensure_ascii=False, indent=1)
        os.replace(tmp, path)
    except Exception:
        try:
            os.unlink(tmp)
        except Exception:
            pass


def _parse_dt(value) -> "datetime | None":
    if not value or not isinstance(value, str):
        return None
    try:
        return datetime.strptime(value.strip(), _DATETIME_FMT)
    except ValueError:
        return None


def _age_s(saved_at) -> "int | None":
    dt = _parse_dt(saved_at)
    if dt is None:
        return None
    try:
        return max(0, int((datetime.now() - dt).total_seconds()))
    except Exception:
        return None


def _format_age(age_s) -> str:
    if age_s is None:
        return "unbekannt"
    if age_s < 60:
        return f"{age_s} Sek."
    mins = age_s // 60
    if mins < 60:
        return f"{mins} Min."
    return f"{mins // 60} Std."


# ------------------------------------------------------------ URL-Kandidaten

def week_key(ref_day: date) -> str:
    iso_year, iso_week, _ = ref_day.isocalendar()
    return f"{iso_year}-W{iso_week:02d}"


def candidate_urls(iso_year: int, iso_week: int) -> "list[str]":
    """Mögliche PDF-URLs dieser KW (Upload-Monat variiert am Monatswechsel).

    Ordner = Monat des Uploads: meist der Wochen-Montag, zur Sicherheit auch
    die zwei Vorwochen (Upload oft in der Vorwoche). Dateiname je einmal mit
    und ohne Nullauffüllung (`39.` / `05.`).
    """
    monday = date.fromisocalendar(iso_year, iso_week, 1)
    months: "list[tuple[int, int]]" = []
    for delta in (0, 7, 14):
        d = monday - timedelta(days=delta)
        if (d.year, d.month) not in months:
            months.append((d.year, d.month))
    urls: "list[str]" = []
    for y, m in months:
        for kw in (str(iso_week), f"{iso_week:02d}"):
            url = (f"{ESSEN_BASE_URL}/wp-content/uploads/{y}/{m:02d}/"
                   f"Mensa-und-Ausser-Haus-{kw}.-KW.pdf")
            if url not in urls:
                urls.append(url)
    return urls


def _download_pdf(url: str, timeout: int = 8) -> "bytes | None":
    """PDF laden oder None (404, kein PDF, zu groß, offline)."""
    try:
        resp = requests.get(
            url, timeout=timeout, stream=True,
            headers={"User-Agent": "EduFlow/1.0"})
    except Exception:
        return None
    try:
        if resp.status_code != 200:
            return None
        buf = b""
        for chunk in resp.iter_content(65536):
            if chunk:
                buf += chunk
                if len(buf) > 8_000_000:
                    return None
        return bytes(buf) if buf.startswith(b"%PDF") else None
    except Exception:
        return None
    finally:
        try:
            resp.close()
        except Exception:
            pass


# ------------------------------------------------------------ PDF-Parsing

def _clean(s: str) -> str:
    s = re.sub(r"\s+", " ", str(s or "")).strip()
    # Extraktions-Artefakt des PDFs ("V ollkorn" statt "Vollkorn").
    return s.replace("V ollkorn", "Vollkorn")


def split_dishes(section: str) -> "tuple[list[dict], str]":
    """Tagesabschnitt -> ([{text, price}], note).

    Jedes Gericht endet mit einer Preisangabe (`7,90 €`); der Text davor
    ist das Gericht (inkl. Allergen-/Zusatzstoffcodes aus dem Plan).
    Resttext ohne Preis ab ~30 Zeichen ist ein Hinweis (z. B. DGE-Zeile).
    """
    parts = _PRICE_RE.split(section or "")
    dishes: "list[dict]" = []
    for i in range(1, len(parts), 2):
        name = _clean(parts[i - 1])
        if name:
            dishes.append({"text": name, "price": f"{parts[i]} €"})
    tail = _clean(parts[-1]) if parts else ""
    note = ""
    if tail:
        if not dishes:
            dishes.append({"text": tail, "price": ""})
        elif len(tail) >= 30:
            note = tail
    return dishes, note


def parse_menu_text(text: str) -> "tuple[dict, str | None]":
    """Gesamttext -> ({Tag: (dishes, note)}, Wochenlabel oder None)."""
    label = None
    m = _HEADER_RE.search(text or "")
    if m:
        d1, m1, d2, m2, y = m.groups()
        label = f"{int(d1)}.{int(m1)}. – {int(d2)}.{int(m2)}.{y}"
    days: dict = {}
    found = list(_DAY_RE.finditer(text or ""))
    for i, hit in enumerate(found):
        name = hit.group(1)
        if name == "Sonnabend":
            name = "Samstag"
        start = hit.end()
        end = found[i + 1].start() if i + 1 < len(found) else len(text)
        dishes, note = split_dishes(text[start:end])
        if name not in days:
            days[name] = (dishes, note)
    return days, label


def parse_pdf(pdf_bytes: bytes, iso_year: int, iso_week: int) -> dict:
    """PDF-Bytes -> Anzeige-Dict {week, label, source_url, days, today}.

    `source_url` setzt der Aufrufer (welcher Kandidat gegriffen hat).
    """
    try:
        from pypdf import PdfReader
    except ImportError:
        raise EssenUnavailable(
            "PDF-Auswertung fehlt (pypdf nicht installiert: "
            "`pip install -r requirements.txt`).")
    try:
        reader = PdfReader(BytesIO(pdf_bytes))
        text = "\n".join([(p.extract_text() or "") for p in reader.pages])
    except Exception as e:
        raise EssenUnavailable(f"PDF konnte nicht gelesen werden: {e}")
    if len(text.strip()) < 50:
        raise EssenUnavailable("PDF enthält keinen lesbaren Text.")
    parsed, label = parse_menu_text(text)
    if not parsed:
        raise EssenUnavailable("Im PDF wurden keine Wochentage gefunden.")

    monday = date.fromisocalendar(iso_year, iso_week, 1)
    if label is None:
        friday = monday + timedelta(days=4)
        label = (f"{monday.day}.{monday.month}. – "
                 f"{friday.day}.{friday.month}.{friday.year}")
    days = {}
    for idx, name in enumerate(DAY_NAMES):
        dishes, note = parsed.get(name, ([], ""))
        days[name] = {
            "date": (monday + timedelta(days=idx)).isoformat(),
            "dishes": dishes,
            "note": note,
        }
    today = date.today()
    today_name = None
    if today.isocalendar()[:2] == (iso_year, iso_week) and today.weekday() < 5:
        today_name = DAY_NAMES[today.weekday()]
    return {
        "week": f"{iso_year}-W{iso_week:02d}",
        "label": label,
        "source_url": "",
        "days": days,
        "today": today_name,
    }


# ------------------------------------------------------------ Hauptzugang

def get_week_menu(ref_day: "date | None" = None,
                  force_refresh: bool = False) -> dict:
    """Wochenplan laden (Cache zuerst). Returns Anzeige-Dict + Cache-Infos.

    Wirft EssenUnavailable, wenn weder frischer Download noch alter Stand
    verfügbar ist.
    """
    ref = ref_day or date.today()
    iso_year, iso_week, _ = ref.isocalendar()
    key = f"{iso_year}-W{iso_week:02d}"
    cached = _read_json(_cache_path(key))
    data = cached.get("data") if isinstance(cached, dict) else None

    if (isinstance(data, dict) and not force_refresh
            and _age_s(cached.get("saved_at")) is not None
            and (_age_s(cached.get("saved_at")) or 0) < ESSEN_TTL_S):
        out = dict(data)
        out["cached"] = True
        out["cache_info"] = (
            f"aus Cache ({_format_age(_age_s(cached.get('saved_at')))} alt)")
        return out

    last_err = "Essenplan-PDF nicht gefunden."
    for url in candidate_urls(iso_year, iso_week):
        pdf = _download_pdf(url)
        if pdf is None:
            continue
        try:
            fresh = parse_pdf(pdf, iso_year, iso_week)
        except EssenUnavailable as e:
            last_err = str(e)
            if "pypdf" in last_err:
                break
            continue
        fresh["source_url"] = url
        try:
            _atomic_write_json(_cache_path(key), {
                "version": 1,
                "saved_at": datetime.now().strftime(_DATETIME_FMT),
                "data": fresh,
            })
        except Exception:
            pass
        fresh["cached"] = False
        fresh["cache_info"] = "frisch geladen"
        return fresh

    if isinstance(data, dict):
        out = dict(data)
        out["cached"] = True
        out["cache_info"] = (
            "offline: Cache "
            f"({_format_age(_age_s(cached.get('saved_at')))} alt)")
        return out
    raise EssenUnavailable(last_err)
