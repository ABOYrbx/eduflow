export const demoMessages = [
  { id: 4101, timestamp: "2026-09-25 14:10:00", timestamp_iso: "2026-09-25T14:10:00", sort_key: "2026-09-25T14:10:00", text: "Erinnerung: Elternabend am Donnerstag um 18 Uhr.", author: "Frau Berger", recipient: "Klasse 8A", type: "sprava", type_label: "Nachricht", additional_data: {}, is_starred: false, is_done: false, done_at: "", reaction_count: 1, created_at: "2026-09-25T14:10:00", is_removed: false },
  { id: 4102, timestamp: "2026-09-24 09:35:00", timestamp_iso: "2026-09-24T09:35:00", sort_key: "2026-09-24T09:35:00", text: "Der Ausflug nach Berlin startet am Freitag um 8:15 Uhr.", author: "Herr Özdemir", recipient: "Klasse 8A", type: "news", type_label: "Neuigkeit", additional_data: { filename: "Packliste.pdf", file: "/cloud/demo-packliste.pdf" }, is_starred: true, is_done: false, done_at: "", reaction_count: 0, created_at: "2026-09-24T09:35:00", is_removed: false },
  { id: 4103, timestamp: "2026-09-23 11:20:00", timestamp_iso: "2026-09-23T11:20:00", sort_key: "2026-09-23T11:20:00", text: "Bitte stimmt bis morgen über den Projekttitel ab.", author: "Klassenrat", recipient: "Klasse 8A", type: "anketa", type_label: "Umfrage", additional_data: {}, is_starred: false, is_done: false, done_at: "", reaction_count: 3, created_at: "2026-09-23T11:20:00", is_removed: false },
  { id: 4104, timestamp: "2026-09-22 12:00:00", timestamp_iso: "2026-09-22T12:00:00", sort_key: "2026-09-22T12:00:00", text: "Danke für eure Rückmeldungen!", author: "Lea Beispiel", recipient: "Frau Berger", type: "sprava", type_label: "Nachricht", additional_data: { textReply: "4101" }, is_starred: false, is_done: false, done_at: "", reaction_count: 0, created_at: "2026-09-22T12:00:00", is_removed: false },
];

const due = (offset: number): string => {
  const d = new Date(); d.setDate(d.getDate() + offset); return d.toISOString().slice(0, 10);
};

export const demoHomework = [
  { id: 5101, type: "homework", title: "Übungsblatt 4, Aufgaben 1–6", subject: "Mathematik", teacher: "Frau Berger", description: "Rechenwege vollständig notieren.", assigned: due(-2), assigned_iso: due(-2), due: due(1), due_display: new Date(`${due(1)}T12:00:00`).toLocaleDateString("de-DE"), status: "offen", is_done: false, is_hidden: false },
  { id: 5102, type: "homework", title: "Vokabeln Unit 3 wiederholen", subject: "Englisch", teacher: "Herr Meyer", description: "Wörter 1 bis 25.", assigned: due(-1), assigned_iso: due(-1), due: due(0), due_display: new Date(`${due(0)}T12:00:00`).toLocaleDateString("de-DE"), status: "heute fällig", is_done: false, is_hidden: false },
  { id: 5103, type: "homework", title: "Lesetagebuch ergänzen", subject: "Deutsch", teacher: "Herr Özdemir", description: "Kapitel 5 und 6.", assigned: due(-4), assigned_iso: due(-4), due: due(-1), due_display: new Date(`${due(-1)}T12:00:00`).toLocaleDateString("de-DE"), status: "überfällig", is_done: false, is_hidden: false },
  { id: 5104, type: "homework", title: "Skizze für das Plakat", subject: "Kunst", teacher: "Frau Lang", description: "Papier oder Tablet.", assigned: due(-8), assigned_iso: due(-8), due: due(-3), due_display: new Date(`${due(-3)}T12:00:00`).toLocaleDateString("de-DE"), status: "erledigt", is_done: true, is_hidden: false },
  { id: 5105, type: "bexam", title: "Lernzielkontrolle: Kräfte", subject: "Physik", teacher: "Frau Berger", description: "Kapitel 2.", assigned: due(-1), assigned_iso: due(-1), due: due(4), due_display: new Date(`${due(4)}T12:00:00`).toLocaleDateString("de-DE"), status: "offen", is_done: false, is_hidden: false },
];

export const demoGrades = [
  { id: 6101, title: "Schularbeit 1", subject: "Mathematik", teacher: "Frau Berger", date_display: "24.09.2026", date_iso: "2026-09-24", sort_key: "2026-09-24T00:00:00", comment: "", grade_display: "2", grade_num: 2, weight: 1, weight_display: "", grade_sub: "", badge: "g12", class_avg: 2.4, class_avg_display: "2,4", is_classic: true },
  { id: 6102, title: "Vokabeltest 3", subject: "Englisch", teacher: "Herr Meyer", date_display: "22.09.2026", date_iso: "2026-09-22", sort_key: "2026-09-22T00:00:00", comment: "", grade_display: "1", grade_num: 1, weight: 1, weight_display: "", grade_sub: "", badge: "g12", class_avg: null, class_avg_display: "", is_classic: true },
  { id: 6103, title: "Interpretation", subject: "Deutsch", teacher: "Herr Özdemir", date_display: "18.09.2026", date_iso: "2026-09-18", sort_key: "2026-09-18T00:00:00", comment: "Gute Belege", grade_display: "2+", grade_num: 1.7, weight: 0.5, weight_display: "½", grade_sub: "", badge: "g12", class_avg: 2.8, class_avg_display: "2,8", is_classic: true },
];

export const demoLessons = [
  { period: "1", time: "07:45–08:30", title: "Mathematik", is_lernzeit: false, teachers: "Frau Berger", rooms: "R204", is_cancelled: false, is_event: false, is_online: false },
  { period: "2–3", time: "08:35–10:20", title: "Lernzeit", is_lernzeit: true, teachers: "", rooms: "Lernraum", is_cancelled: false, is_event: false, is_online: false },
  { period: "4", time: "10:25–11:10", title: "Englisch", is_lernzeit: false, teachers: "Herr Meyer", rooms: "R108", is_cancelled: true, is_event: false, is_online: false },
  { period: "5", time: "11:15–12:00", title: "Physik", is_lernzeit: false, teachers: "Frau Berger", rooms: "R305", is_cancelled: false, is_event: false, is_online: true },
];

export const demoRecipients = [
  { id: "Teacher7", name: "Frau Berger", kind: "teacher", detail: "Mathematik, Physik" },
  { id: "Teacher8", name: "Herr Özdemir", kind: "teacher", detail: "Deutsch" },
  { id: "Student9", name: "Lea Beispiel", kind: "student", detail: "8A" },
];
