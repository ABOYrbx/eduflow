export const demoMessages = [
  { id: 4101, timestamp: "2026-09-25 14:10:00", timestamp_iso: "2026-09-25T14:10:00", sort_key: "2026-09-25T14:10:00", text: "Reminder: parent-teacher conferences on Thursday at 6 PM.", author: "Ms. Berger", recipient: "Class 8A", type: "sprava", type_label: "Message", additional_data: {}, is_starred: false, is_done: false, done_at: "", reaction_count: 1, created_at: "2026-09-25T14:10:00", is_removed: false },
  { id: 4102, timestamp: "2026-09-24 09:35:00", timestamp_iso: "2026-09-24T09:35:00", sort_key: "2026-09-24T09:35:00", text: "The field trip to Berlin starts Friday at 8:15 AM.", author: "Mr. Özdemir", recipient: "Class 8A", type: "news", type_label: "News", additional_data: { filename: "PackingList.pdf", file: "/cloud/demo-packing-list.pdf" }, is_starred: true, is_done: false, done_at: "", reaction_count: 0, created_at: "2026-09-24T09:35:00", is_removed: false },
  { id: 4103, timestamp: "2026-09-23 11:20:00", timestamp_iso: "2026-09-23T11:20:00", sort_key: "2026-09-23T11:20:00", text: "Please vote on the project title by tomorrow.", author: "Student council", recipient: "Class 8A", type: "anketa", type_label: "Poll", additional_data: {}, is_starred: false, is_done: false, done_at: "", reaction_count: 3, created_at: "2026-09-23T11:20:00", is_removed: false },
  { id: 4104, timestamp: "2026-09-22 12:00:00", timestamp_iso: "2026-09-22T12:00:00", sort_key: "2026-09-22T12:00:00", text: "Thanks for your feedback!", author: "Lea Example", recipient: "Ms. Berger", type: "sprava", type_label: "Message", additional_data: { textReply: "4101" }, is_starred: false, is_done: false, done_at: "", reaction_count: 0, created_at: "2026-09-22T12:00:00", is_removed: false },
];

const due = (offset: number): string => {
  const d = new Date(); d.setDate(d.getDate() + offset); return d.toISOString().slice(0, 10);
};

export const demoHomework = [
  { id: 5101, type: "homework", title: "Practice sheet 4, exercises 1–6", subject: "Math", teacher: "Ms. Berger", description: "Write down all solution steps.", assigned: due(-2), assigned_iso: due(-2), due: due(1), due_display: new Date(`${due(1)}T12:00:00`).toLocaleDateString("en-US"), status: "offen", is_done: false, is_hidden: false },
  { id: 5102, type: "homework", title: "Review Unit 3 vocabulary", subject: "English", teacher: "Mr. Meyer", description: "Words 1 through 25.", assigned: due(-1), assigned_iso: due(-1), due: due(0), due_display: new Date(`${due(0)}T12:00:00`).toLocaleDateString("en-US"), status: "heute fällig", is_done: false, is_hidden: false },
  { id: 5103, type: "homework", title: "Complete the reading journal", subject: "German", teacher: "Mr. Özdemir", description: "Chapters 5 and 6.", assigned: due(-4), assigned_iso: due(-4), due: due(-1), due_display: new Date(`${due(-1)}T12:00:00`).toLocaleDateString("en-US"), status: "überfällig", is_done: false, is_hidden: false },
  { id: 5104, type: "homework", title: "Sketch for the poster", subject: "Art", teacher: "Ms. Lang", description: "Paper or tablet.", assigned: due(-8), assigned_iso: due(-8), due: due(-3), due_display: new Date(`${due(-3)}T12:00:00`).toLocaleDateString("en-US"), status: "erledigt", is_done: true, is_hidden: false },
  { id: 5105, type: "bexam", title: "Quiz: forces", subject: "Physics", teacher: "Ms. Berger", description: "Chapter 2.", assigned: due(-1), assigned_iso: due(-1), due: due(4), due_display: new Date(`${due(4)}T12:00:00`).toLocaleDateString("en-US"), status: "offen", is_done: false, is_hidden: false },
];

export const demoGrades = [
  { id: 6101, title: "Written test 1", subject: "Math", teacher: "Ms. Berger", date_display: "09/24/2026", date_iso: "2026-09-24", sort_key: "2026-09-24T00:00:00", comment: "", grade_display: "2", grade_num: 2, weight: 1, weight_display: "", grade_sub: "", badge: "g12", class_avg: 2.4, class_avg_display: "2.4", is_classic: true },
  { id: 6102, title: "Vocabulary quiz 3", subject: "English", teacher: "Mr. Meyer", date_display: "09/22/2026", date_iso: "2026-09-22", sort_key: "2026-09-22T00:00:00", comment: "", grade_display: "1", grade_num: 1, weight: 1, weight_display: "", grade_sub: "", badge: "g12", class_avg: null, class_avg_display: "", is_classic: true },
  { id: 6103, title: "Literary analysis", subject: "German", teacher: "Mr. Özdemir", date_display: "09/18/2026", date_iso: "2026-09-18", sort_key: "2026-09-18T00:00:00", comment: "Good evidence", grade_display: "2+", grade_num: 1.7, weight: 0.5, weight_display: "½", grade_sub: "", badge: "g12", class_avg: 2.8, class_avg_display: "2.8", is_classic: true },
];

export const demoLessons = [
  { period: "1", time: "07:45–08:30", title: "Math", is_lernzeit: false, teachers: "Ms. Berger", rooms: "R204", is_cancelled: false, is_event: false, is_online: false },
  { period: "2–3", time: "08:35–10:20", title: "Study hall", is_lernzeit: true, teachers: "", rooms: "Study room", is_cancelled: false, is_event: false, is_online: false },
  { period: "4", time: "10:25–11:10", title: "English", is_lernzeit: false, teachers: "Mr. Meyer", rooms: "R108", is_cancelled: true, is_event: false, is_online: false },
  { period: "5", time: "11:15–12:00", title: "Physics", is_lernzeit: false, teachers: "Ms. Berger", rooms: "R305", is_cancelled: false, is_event: false, is_online: true },
];

export const demoRecipients = [
  { id: "Teacher7", name: "Ms. Berger", kind: "teacher", detail: "Math, Physics" },
  { id: "Teacher8", name: "Mr. Özdemir", kind: "teacher", detail: "German" },
  { id: "Student9", name: "Lea Example", kind: "student", detail: "8A" },
];
