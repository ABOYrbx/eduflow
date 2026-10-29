/**
 * Wire-Typen der Web-UI — 1:1 die Dicts aus `GET /api/v1/openapi.json`
 * (siehe `apps/api/src/system/system.controller.ts`). Bewusst als lokale
 * Typen und nicht aus `@eduflow/contracts`: die Felder sind das, was das
 * Backend wirklich liefert, inklusive der Listen-Hülle mit `counts`.
 *
 * `code`/`status`/`type` sind stabile Vokabulare und werden nie
 * übersetzt; Anzeigetexte kommen über `t()` aus den Katalogen.
 */

/** Fehler der API: immer `{error, code}` (siehe `ApiExceptionFilter`). */
export type ApiError = { error?: string; code?: string };

/** Listen-Hülle; `limit` 50/max 200 (siehe `common/pagination.ts`). */
export type Page<T> = { items: T[]; total: number; limit: number; offset: number; counts?: Record<string, number>; cache_info?: string };

export type Message = {
  id: number;
  text: string;
  author: string;
  recipient: string;
  type: string;
  type_label: string;
  timestamp: string;
  timestamp_iso: string;
  additional_data?: Record<string, unknown>;
  attachments?: Array<{ name: string; url: string }>;
  is_starred: boolean;
  is_done?: boolean;
  done_at?: string;
  reaction_count: number;
};

/** Likes + Antworten zu einer Nachricht (`messages/:id/thread`). */
export type Thread = {
  likes: Array<{ name: string; date: string }>;
  replies: Array<{ name: string; date: string; text: string }>;
};

export type Homework = {
  id: number;
  title: string;
  subject: string;
  description: string;
  teacher: string;
  author?: string;
  assigned?: string;
  assigned_iso?: string;
  due: string;
  due_display: string;
  status: string;
  is_done: boolean;
  is_hidden: boolean;
  is_starred?: boolean;
  done_at?: string;
  type: string;
  type_label?: string;
};

export type Lesson = {
  period: string;
  time: string;
  title: string;
  teachers: string;
  rooms: string;
  is_lernzeit: boolean;
  is_cancelled: boolean;
  is_online: boolean;
  is_event?: boolean;
};

export type Grade = {
  id: number;
  title: string;
  subject: string;
  teacher: string;
  date_display: string;
  date_iso: string;
  grade_display: string;
  grade_num: number | null;
  weight: number;
  weight_display: string;
  grade_sub: string;
  badge: string;
  class_avg_display: string;
  comment: string;
};

/** Kalender-, Prüfungs- und Anwesenheitsereignisse (`school/agenda`). */
export type AgendaItem = { id: number; kind: string; date: string; title?: string; text: string; subject?: string };

/** Eine Zeile der Vertretungswoche (`substitutions/week`). */
export type Substitution = { date: string; day_label: string; changes: Array<{ class?: string; lesson: string; title: string; action: string }> };

/** Antwort von `settings` (GET) und `settings` (PUT). */
export type Settings = {
  schema: Array<{
    key: string;
    kind: string;
    label: string;
    options?: string[][];
    default: unknown;
    min?: number;
    max?: number;
    hint?: string;
    maxlength?: number;
    section?: string;
    placeholder?: string;
  }>;
  values: Record<string, unknown>;
};

export type Weather = {
  city: string;
  today: { temp: number; max: number; min: number; desc: string; icon: string };
  tomorrow: { max: number; min: number; desc: string; icon?: string };
  day3: { max: number; min: number; desc: string; icon?: string };
};

/** Anmeldete Geräte (`devices`). Im Fake-Provider gibt es `current`/`revoked`,
 *  im echten EduPage-Provider stattdessen ein gekürztes `short`. */
export type Device = { id: string; device: string; created: string; expires: string; short?: string; current?: boolean; revoked?: boolean };

export type Recipient = { id: string; name: string; kind?: string; detail?: string };

/** Antwort von `timetable/day` und `timetable/week`. */
export type TimetableData = {
  day_label?: string;
  lessons?: Lesson[];
  week_label?: string;
  days?: Array<{ date: string; day_name: string; day_date: string; is_today?: boolean; lessons: Lesson[] }>;
};
