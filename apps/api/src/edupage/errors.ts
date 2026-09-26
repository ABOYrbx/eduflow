/** EduPage-Fehler (Port von `edupage_api.exceptions`, Paket N-A).
 *
 * Die Klassen transportieren nur die Fehlerart; die deutschen
 * API-Texte + Codes vergibt der Auth-Service wie Python (`api/auth.py`,
 * `api/core.py::edupage_login_error`). Keine Secrets, keine HTML-Ausschnitte.
 */
export class EdupageError extends Error {}

export class BadCredentialsError extends EdupageError {}
export class CaptchaError extends EdupageError {}
export class SecondFactorFailedError extends EdupageError {}
export class MissingDataError extends EdupageError {}
export class RequestError extends EdupageError {}
export class ExpiredSessionError extends EdupageError {}
export class Base64DecodeError extends EdupageError {}
