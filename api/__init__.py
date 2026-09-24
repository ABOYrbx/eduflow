"""EduFlow API v1 – Paketverzeichnis.

Der Blueprint `bp` (Präfix `/api/v1`) ist der einzige Anbindungspunkt an die
App (eine Zeile in app.py). Alle Ressourcen-Pakete (Auth, Nachrichten,
Hausaufgaben, Stundenplan, Noten, Essen/Wetter, Einstellungen) registrieren
ihre Routen auf diesem Blueprint und nutzen ausschließlich das Kernmodul
`api.core` plus die bestehenden Helper aus app.py und cache.py.
"""

from flask import Blueprint

bp = Blueprint("api_v1", __name__, url_prefix="/api/v1")

# Teilmodule binden ihre Routen an `bp` (Paket B: Nachrichten und Threads).
# Der Import steht bewusst hinter der Blueprint-Definition; app.py fasst
# nur `bp` an, nie die Teilmodule direkt.
from api import messages as _messages  # noqa: F401,E402

# Ressourcen-Pakete registrieren ihre Routen auf dem Blueprint oben.
# Jedes Paket trägt hier genau eine Importzeile ein (kein App-Import
# auf Modulebene in den Paketen, um Importzyklen zu vermeiden).
from api import auth  # noqa: E402,F401
from api import homework  # noqa: E402,F401
from api import timetable  # noqa: E402,F401
from api import grades  # noqa: E402,F401
from api import meta  # noqa: E402,F401
from api import settings  # noqa: E402,F401
from api import system  # noqa: E402,F401
