"""Schulalltag: Vertretungen und Kalenderereignisse für Schüler/Eltern."""

from datetime import date, timedelta

from flask import request

from api import bp
from api.core import api_error, token_required


def _parse_date(raw, default):
    if not raw:
        return default
    try:
        return date.fromisoformat(raw.strip())
    except (ValueError, TypeError, AttributeError):
        raise ValueError("Das Datum muss im Format JJJJ-MM-TT angegeben werden.")


def _login():
    from api.timetable import _login as timetable_login
    return timetable_login()


def _change_dict(change):
    action = getattr(change, "action", "")
    action = getattr(action, "value", action)
    lesson = getattr(change, "lesson_n", "")
    if isinstance(lesson, tuple):
        lesson = "–".join(str(part) for part in lesson)
    return {
        "class": str(getattr(change, "change_class", "") or ""),
        "lesson": str(lesson),
        "title": str(getattr(change, "title", "") or ""),
        "action": str(action or ""),
    }


def build_substitutions(edupage, selected):
    monday = selected - timedelta(days=selected.weekday())
    from app import GERMAN_WEEKDAYS
    user_class = ""
    try:
        student_id = getattr(edupage, "_selected_child_id", None) or edupage.get_user_id()
        student = edupage.get_student(student_id)
        class_id = getattr(student, "class_id", None)
        if class_id is not None:
            user_class = next(
                (str(getattr(item, "name", "")) for item in (edupage.get_classes() or [])
                 if str(getattr(item, "class_id", "")) == str(class_id)),
                "",
            )
    except Exception:
        user_class = ""
    days = []
    for index in range(5):
        current = monday + timedelta(days=index)
        changes = edupage.get_timetable_changes(current) or []
        if user_class:
            changes = [item for item in changes
                       if str(getattr(item, "change_class", "")) == user_class]
        days.append({
            "date": current.isoformat(),
            "day_label": f"{GERMAN_WEEKDAYS[current.weekday()]} "
                         f"{current.strftime('%d.%m.%Y')}",
            "changes": [_change_dict(item) for item in changes],
        })
    return {
        "monday": monday.isoformat(),
        "week_label": "Woche %s – %s" % (
            monday.strftime("%d.%m."),
            (monday + timedelta(days=4)).strftime("%d.%m.%Y")),
        "days": days,
    }


@bp.route("/substitutions/week", methods=["GET"])
@token_required
def api_substitutions_week():
    """Vertretungsänderungen Montag bis Freitag für die gewählte Woche."""
    try:
        selected = _parse_date(request.args.get("day"), date.today())
    except ValueError as exc:
        return api_error(str(exc), "VALIDATION", 400)
    error, login = _login()
    if error is not None:
        return error
    edupage, _username, _subdomain = login

    try:
        payload = build_substitutions(edupage, selected)
    except Exception:
        return api_error("Vertretungsplan konnte nicht geladen werden.",
                         "UPSTREAM", 502)

    return payload, 200


def build_agenda(edupage, username, subdomain, start, end, force_refresh=False):
    from app import (
        EXAM_TYPES,
        _event_type_str,
        event_to_dict,
        get_timeline_cached,
        homework_to_dict,
    )
    events, _requests, _effective, cache_meta = get_timeline_cached(
        edupage, subdomain, username, start, force_refresh)

    calendar_types = {
        "ctevent", "bmeeting", "culture", "event", "excursion",
        "parentsevening", "schoolevent", "trip", "meeting", "freeday",
        "holiday", "sholiday", "project",
    }
    attendance_types = {
        "student_absent", "ospravedlnenka", "h_attendance", "pipnutie",
    }
    wanted = calendar_types | attendance_types | set(EXAM_TYPES)
    items = []
    for event in events:
        event_type = _event_type_str(event)
        if event_type not in wanted:
            continue
        stamp = getattr(event, "timestamp", None)
        if not hasattr(stamp, "date"):
            continue
        kind = (
            "attendance" if event_type in attendance_types
            else "exam" if event_type in EXAM_TYPES
            else "event"
        )
        item = homework_to_dict(event) if kind == "exam" else event_to_dict(event)
        event_day = stamp.date()
        if kind == "exam" and item.get("due"):
            try:
                event_day = date.fromisoformat(item["due"])
            except ValueError:
                pass
        if event_day < start or event_day > end:
            continue
        item["kind"] = kind
        item["date"] = event_day.isoformat()
        items.append(item)

    items.sort(key=lambda item: (
        item["date"], item.get("timestamp_iso", item.get("assigned_iso", "")),
        str(item.get("title", item.get("text", ""))).casefold()))
    return {
        "items": items,
        "total": len(items),
        "since": start.isoformat(),
        "until": end.isoformat(),
        "cache_info": (cache_meta or {}).get("cache_info", ""),
    }


@bp.route("/school/agenda", methods=["GET"])
@token_required
def api_school_agenda():
    """Schultermine, Prüfungen und persönliche Anwesenheitsmeldungen."""
    try:
        start = _parse_date(request.args.get("since"), date.today() - timedelta(days=30))
        end = _parse_date(request.args.get("until"), date.today() + timedelta(days=60))
    except ValueError as exc:
        return api_error(str(exc), "VALIDATION", 400)
    if end < start or (end - start).days > 366:
        return api_error("Der Zeitraum darf höchstens ein Jahr umfassen.",
                         "VALIDATION", 400)

    error, login = _login()
    if error is not None:
        return error
    edupage, username, subdomain = login

    try:
        payload = build_agenda(edupage, username, subdomain, start, end,
                               request.args.get("refresh") == "1")
    except Exception:
        return api_error("Schultermine konnten nicht geladen werden.",
                         "UPSTREAM", 502)
    return payload, 200
