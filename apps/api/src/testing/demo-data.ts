/**
 * Absätze: `\n\n` trennt Absätze, so wie es echte EduPage-Nachrichten tun.
 * Web (`pre-wrap` in `compat.css`), SwiftUI (`Text`) und Compose (`Text`)
 * stellen die Umbrüche dar; die Demo soll diese Darstellung zeigen.
 */
const paragraphs = (...parts: string[]): string => parts.join("\n\n");

export const demoMessages = [
  {
    id: 4101, timestamp: "2026-09-25 14:10:00", timestamp_iso: "2026-09-25T14:10:00", sort_key: "2026-09-25T14:10:00",
    text: paragraphs(
      "Dear Class 8A,",
      "parent-teacher conferences take place this Thursday from 4:00 pm to 7:30 pm in the main building. I have reserved six time slots for our class; the sign-up sheet is in the office and you can also add your name online.",
      "Please pick a slot before Wednesday so that I can prepare your individual progress report beforehand. If none of the slots work for your family, write to me and I will find an alternative on Friday morning.",
      "A short reminder about the format: the first ten minutes are a general update from me, the following fifteen minutes are your own slot with your parents, and the last slot of the hour is reserved for parents who could not come earlier.",
      "Please bring your current grade sheet and your reading journal. It is much easier to talk about concrete work than about a single number.",
      "Kind regards,\nMs. Berger",
    ),
    author: "Ms. Berger", recipient: "Class 8A", type: "sprava", type_label: "Message", additional_data: {}, is_starred: false, is_done: false, done_at: "", reaction_count: 1, created_at: "2026-09-25T14:10:00", is_removed: false,
  },
  {
    id: 4102, timestamp: "2026-09-24 09:35:00", timestamp_iso: "2026-09-24T09:35:00", sort_key: "2026-09-24T09:35:00",
    text: paragraphs(
      "Dear Class 8A,",
      "as announced in class, our class trip to Berlin will start on Friday at 8:15 am in front of the main entrance. The bus leaves punctually, so please be there five minutes early.",
      "We will first visit the Museum Island and take a guided tour of the Pergamon collection. After lunch we walk along the Spree and continue to the Tiergarten, where a boat tour is reserved for the whole class.",
      "Because of the afternoon program, lessons in the first two periods will be cancelled. The bus departs for the return trip at 4:30 pm and should reach us by 7:00 pm.",
      "The attached packing list contains everything you need. Please hand in the signed permission slip by Tuesday; without it you cannot join the trip.",
      "If you have any questions, please speak to me during the study hall on Wednesday.",
      "Kind regards,\nMr. Özdemir",
    ),
    author: "Mr. Özdemir", recipient: "Class 8A", type: "news", type_label: "News", additional_data: { filename: "PackingList.pdf", file: "/cloud/demo-packing-list.pdf" }, is_starred: true, is_done: false, done_at: "", reaction_count: 0, created_at: "2026-09-24T09:35:00", is_removed: false,
  },
  {
    id: 4103, timestamp: "2026-09-23 11:20:00", timestamp_iso: "2026-09-23T11:20:00", sort_key: "2026-09-23T11:20:00",
    text: paragraphs(
      "Hi everyone,",
      "we need your vote on the title for our class project by tomorrow evening. The three options on the ballot are \"Water for tomorrow\", \"City in transition\" and \"Our neighborhood, seen differently\".",
      "You can change your vote as often as you like until the poll closes. The ballot is anonymous and only the total number of votes per option is published.",
      "We will announce the winning title in the assembly on Monday, so a strong participation really matters.",
      "If you have an idea for a completely different title, reply to this message or come to the council meeting on Thursday during the study hall.",
      "Thank you!\nStudent council",
    ),
    author: "Student council", recipient: "Class 8A", type: "anketa", type_label: "Poll", additional_data: {}, is_starred: false, is_done: false, done_at: "", reaction_count: 3, created_at: "2026-09-23T11:20:00", is_removed: false,
  },
  // Antworten auf 4101 (ms. berger -> klasse 8a).
  {
    id: 4104, timestamp: "2026-09-25 14:12:00", timestamp_iso: "2026-09-25T14:12:00", sort_key: "2026-09-25T14:12:00",
    text: paragraphs(
      "Thank you for the detailed information.",
      "I signed up for 5:10 pm and brought my grade sheet as you asked.",
      "Could you also show my parents the reading journal from the last two units? They would like to know what we are working on at the moment.",
    ),
    author: "Lea Example", recipient: "Ms. Berger", type: "sprava", type_label: "Message", additional_data: { textReply: "4101" }, is_starred: false, is_done: false, done_at: "", reaction_count: 0, created_at: "2026-09-25T14:12:00", is_removed: false,
  },
  {
    id: 4110, timestamp: "2026-09-25 16:40:00", timestamp_iso: "2026-09-25T16:40:00", sort_key: "2026-09-25T16:40:00",
    text: paragraphs(
      "Hello Ms. Berger,",
      "my parents can only come on Friday. Is the Friday morning slot still free, and could you talk through the chemistry grade with them as well?",
      "Thank you in advance!",
    ),
    author: "Jonas Example", recipient: "Ms. Berger", type: "sprava", type_label: "Message", additional_data: { textReply: "4101" }, is_starred: false, is_done: false, done_at: "", reaction_count: 0, created_at: "2026-09-25T16:40:00", is_removed: false,
  },
  {
    id: 4111, timestamp: "2026-09-25 17:05:00", timestamp_iso: "2026-09-25T17:05:00", sort_key: "2026-09-25T17:05:00",
    text: paragraphs(
      "Hello Jonas,",
      "Friday at 9:00 am is still free for our class. Both of you are welcome to come; we will talk about the reading journal first and then about the chemistry test.",
      "Please confirm the time with me on Thursday morning so that I can keep the slot reserved.",
    ),
    author: "Ms. Berger", recipient: "Jonas Example", type: "sprava", type_label: "Message", additional_data: { textReply: "4101" }, is_starred: false, is_done: false, done_at: "", reaction_count: 0, created_at: "2026-09-25T17:05:00", is_removed: false,
  },
  // Antworten auf 4102 (ausflug nach berlin).
  {
    id: 4112, timestamp: "2026-09-24 11:20:00", timestamp_iso: "2026-09-24T11:20:00", sort_key: "2026-09-24T11:20:00",
    text: paragraphs(
      "Hello Mr. Özdemir,",
      "my parents will hand in the permission slip tomorrow.",
      "Two questions about the day: do we need warm clothing? The forecast says it will rain in the afternoon. And may we bring our own lunch, or do we eat somewhere together?",
    ),
    author: "Lea Example", recipient: "Mr. Özdemir", type: "news", type_label: "News", additional_data: { textReply: "4102" }, is_starred: false, is_done: false, done_at: "", reaction_count: 0, created_at: "2026-09-24T11:20:00", is_removed: false,
  },
  {
    id: 4113, timestamp: "2026-09-24 12:02:00", timestamp_iso: "2026-09-24T12:02:00", sort_key: "2026-09-24T12:02:00",
    text: paragraphs(
      "Hello Lea,",
      "yes, please bring warm and rainproof clothing. We will be outside for a good part of the afternoon, and the boat tour takes place in the open as well.",
      "We eat together in a restaurant near the museum, so please bring some money for your own part. I will hand in the list of participants on Tuesday morning.",
    ),
    author: "Mr. Özdemir", recipient: "Lea Example", type: "news", type_label: "News", additional_data: { textReply: "4102" }, is_starred: false, is_done: false, done_at: "", reaction_count: 0, created_at: "2026-09-24T12:02:00", is_removed: false,
  },
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
