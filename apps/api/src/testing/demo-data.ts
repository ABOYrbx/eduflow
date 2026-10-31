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
  {
    id: 4106, timestamp: "2026-09-25 08:05:00", timestamp_iso: "2026-09-25T08:05:00", sort_key: "2026-09-25T08:05:00",
    text: paragraphs(
      "Dear Class 8A,",
      "the unit test I announced for this week moves to next Tuesday. I want to give you the extra lesson on conditionals first, and testing the same grammar two days later helps nobody.",
      "Next Tuesday, second period, same room. Please review pages 44 to 61 in the meantime.",
      "Kind regards,\nMr. Meyer",
    ),
    author: "Mr. Meyer", recipient: "Class 8A", type: "news", type_label: "News", additional_data: {}, is_starred: false, is_done: false, done_at: "", reaction_count: 1, created_at: "2026-09-25T08:05:00", is_removed: false,
  },
  {
    id: 4107, timestamp: "2026-09-24 15:15:00", timestamp_iso: "2026-09-24T15:15:00", sort_key: "2026-09-24T15:15:00",
    text: paragraphs(
      "Hello all,",
      "the poster project has a second round: we will exhibit the best sketches in the entrance hall, so everyone gets an audience.",
      "Bring your finished draft to the next art lesson. If you have not started yet, talk to me beforehand rather than on Monday morning.",
      "Kind regards,\nMs. Lang",
    ),
    author: "Ms. Lang", recipient: "Class 8A", type: "news", type_label: "News", additional_data: {}, is_starred: false, is_done: false, done_at: "", reaction_count: 2, created_at: "2026-09-24T15:15:00", is_removed: false,
  },
  // Chat der Klasse: zeigt die neuen Personen als Autoren.
  {
    id: 4105, timestamp: "2026-09-26 09:02:00", timestamp_iso: "2026-09-26T09:02:00", sort_key: "2026-09-26T09:02:00",
    text: paragraphs(
      "Morning everyone,",
      "I uploaded the photos from the museum trip to the class drive. The folder is 8A/Berlin if anyone still needs a picture of the boat tour.",
      "If you send me yours tonight, I will add them all to one album.",
    ),
    author: "Jonas Example", recipient: "Class 8A", type: "chat", type_label: "Chat", additional_data: {}, is_starred: false, is_done: false, done_at: "", reaction_count: 4, created_at: "2026-09-26T09:02:00", is_removed: false,
  },
  {
    id: 4115, timestamp: "2026-09-26 09:20:00", timestamp_iso: "2026-09-26T09:20:00", sort_key: "2026-09-26T09:20:00",
    text: paragraphs(
      "Thanks, I was looking for exactly those two from the Spree.",
      "Mine are in, I took mostly the Pergamon hall.",
    ),
    author: "Miriam Example", recipient: "Class 8A", type: "chat", type_label: "Chat", additional_data: { textReply: "4105" }, is_starred: false, is_done: false, done_at: "", reaction_count: 0, created_at: "2026-09-26T09:20:00", is_removed: false,
  },
  {
    id: 4116, timestamp: "2026-09-26 09:41:00", timestamp_iso: "2026-09-26T09:41:00", sort_key: "2026-09-26T09:41:00",
    text: paragraphs(
      "Album link: I made it public.",
      "Please do not download the whole thing at once, the drive is already at 80 percent.",
    ),
    author: "Sofia Example", recipient: "Class 8A", type: "chat", type_label: "Chat", additional_data: { textReply: "4105" }, is_starred: false, is_done: false, done_at: "", reaction_count: 0, created_at: "2026-09-26T09:41:00", is_removed: false,
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
  {
    id: 4117, timestamp: "2026-09-27 08:15:00", timestamp_iso: "2026-09-27T08:15:00", sort_key: "2026-09-27T08:15:00",
    text: paragraphs(
      "Dear Class 8A,",
      "the school library has extended its opening hours for the autumn term. From now on it is open every day from 7:30 am to 5:00 pm, including during the lunch break.",
      "You can borrow up to five books at a time and keep them for three weeks. Renewals are possible online, and the new reading corner on the first floor has quiet desks with power outlets.",
      "I would like to encourage everyone to use the library for the research phase of our project. The librarian, Ms. Hartmann, has prepared a short guide to the catalogue that I will hand out in class.",
      "If you need help finding sources, write to me or come to the study hall on Wednesday. A well-documented project is half the grade.",
      "Kind regards,\\nMr. Meyer",
    ),
    author: "Mr. Meyer", recipient: "Class 8A", type: "news", type_label: "News", additional_data: {}, is_starred: false, is_done: false, done_at: "", reaction_count: 6, created_at: "2026-09-27T08:15:00", is_removed: false,
  },
  {
    id: 4118, timestamp: "2026-09-28 09:00:00", timestamp_iso: "2026-09-28T09:00:00", sort_key: "2026-09-28T09:00:00",
    text: paragraphs(
      "Dear students,",
      "this is a reminder that the mathematics competition registration closes on Friday. The first round takes place during the fourth and fifth periods and lasts ninety minutes.",
      "You do not need to prepare special material; the problems are based on the curriculum up to Unit 5. Calculators are not allowed, but you may use a ruler and compass.",
      "The three best results of our class will represent us in the regional round in November. Even if you do not win, the problems are a good exercise for the upcoming test.",
      "Please sign up with me during the break or by email. I need your full name and your student number.",
      "Kind regards,\\nMs. Berger",
    ),
    author: "Ms. Berger", recipient: "Class 8A", type: "sprava", type_label: "Message", additional_data: {}, is_starred: false, is_done: false, done_at: "", reaction_count: 7, created_at: "2026-09-28T09:00:00", is_removed: false,
  },
  {
    id: 4119, timestamp: "2026-09-29 10:20:00", timestamp_iso: "2026-09-29T10:20:00", sort_key: "2026-09-29T10:20:00",
    text: paragraphs(
      "Dear Class 8A,",
      "the chemistry lab safety briefing takes place on Monday in room 305. Everyone must attend before we can start the first experiment.",
      "We will cover protective equipment, emergency exits, the location of the fire extinguisher and how to handle broken glass. You will also sign a short safety agreement.",
      "Please wear closed shoes and tie back long hair. If you are absent, you must catch up with me before the next lesson.",
      "The first experiment will be a simple titration, so read the chapter on acids and bases over the weekend.",
      "Kind regards,\\nMr. Özdemir",
    ),
    author: "Mr. Özdemir", recipient: "Class 8A", type: "news", type_label: "News", additional_data: {}, is_starred: false, is_done: false, done_at: "", reaction_count: 3, created_at: "2026-09-29T10:20:00", is_removed: false,
  },
  {
    id: 4120, timestamp: "2027-01-15 10:00:00", timestamp_iso: "2027-01-15T10:00:00", sort_key: "2027-01-15T10:00:00",
    text: paragraphs(
      "Dear Class 8A,",
      "happy new year! The second term starts on Monday with a slightly changed timetable. Please check the updated schedule on the notice board.",
      "We will continue with the topics we started in autumn and add a new project on renewable energy. Groups will be formed in the first week.",
      "Make sure you bring all your materials from last term, especially your reading journal and the grade sheet. We will review the autumn results together.",
      "If you have questions about the new schedule, come to me during the break.",
      "Kind regards,\\nMr. Özdemir",
    ),
    author: "Mr. Özdemir", recipient: "Class 8A", type: "sprava", type_label: "Message", additional_data: {}, is_starred: false, is_done: false, done_at: "", reaction_count: 4, created_at: "2027-01-15T10:00:00", is_removed: false,
  },
  {
    id: 4121, timestamp: "2028-02-10 09:30:00", timestamp_iso: "2028-02-10T09:30:00", sort_key: "2028-02-10T09:30:00",
    text: paragraphs(
      "Dear Class 8A,",
      "the school anniversary celebration takes place on March 3. Our class will present the results of the renewable energy project in the main hall.",
      "Each group needs a poster, a short talk and a small demonstration. Please rehearse your presentation at least twice before the event.",
      "Parents and guests are invited, so dress neatly and arrive fifteen minutes early. The program starts at 5:00 pm and ends around 7:30 pm.",
      "I am proud of the work you have done over the last two years and look forward to seeing it presented.",
      "Kind regards,\\nMs. Berger",
    ),
    author: "Ms. Berger", recipient: "Class 8A", type: "sprava", type_label: "Message", additional_data: {}, is_starred: true, is_done: false, done_at: "", reaction_count: 10, created_at: "2028-02-10T09:30:00", is_removed: false,
  },
  {
    id: 4122, timestamp: "2026-10-05 08:00:00", timestamp_iso: "2026-10-05T08:00:00", sort_key: "2026-10-05T08:00:00",
    text: paragraphs(
      "Dear Class 8A,",
      "the science fair preparation begins next week. Each group should choose a topic and register it with me by Wednesday.",
      "Topics can range from simple experiments to larger projects. Please make sure your idea is safe and feasible within the time we have.",
      "We will have two lessons in the lab for preparation and one for the presentation. Parents are invited to the final exhibition.",
      "I look forward to creative ideas.",
      "Kind regards,\nMs. Berger",
    ),
    author: "Ms. Berger", recipient: "Class 8A", type: "news", type_label: "News", additional_data: {}, is_starred: false, is_done: false, done_at: "", reaction_count: 4, created_at: "2026-10-05T08:00:00", is_removed: false,
  },
  {
    id: 4123, timestamp: "2026-10-06 09:30:00", timestamp_iso: "2026-10-06T09:30:00", sort_key: "2026-10-06T09:30:00",
    text: paragraphs(
      "Hello everyone,",
      "the football tournament sign-up is open until Friday. Teams of five students can register at the sports office.",
      "Matches take place during the sports lessons in the second week of October. Please bring your sports clothes and a water bottle.",
      "There will be a small prize for the winning team and a fair-play award for the most respectful team.",
      "Good luck,\nStudent council",
    ),
    author: "Student council", recipient: "Class 8A", type: "anketa", type_label: "Poll", additional_data: {}, is_starred: false, is_done: false, done_at: "", reaction_count: 6, created_at: "2026-10-06T09:30:00", is_removed: false,
  },
  {
    id: 4124, timestamp: "2026-10-07 11:15:00", timestamp_iso: "2026-10-07T11:15:00", sort_key: "2026-10-07T11:15:00",
    text: paragraphs(
      "Dear Class 8A,",
      "please remember to bring your signed permission slips for the museum trip. Without them you cannot participate.",
      "The trip leaves at 8:15 am and returns around 7:00 pm. Pack a lunch and wear comfortable shoes.",
      "If you have any questions, ask me during the break.",
      "Kind regards,\nMr. Özdemir",
    ),
    author: "Mr. Özdemir", recipient: "Class 8A", type: "news", type_label: "News", additional_data: {}, is_starred: false, is_done: false, done_at: "", reaction_count: 2, created_at: "2026-10-07T11:15:00", is_removed: false,
  },
  {
    id: 4125, timestamp: "2026-10-08 13:00:00", timestamp_iso: "2026-10-08T13:00:00", sort_key: "2026-10-08T13:00:00",
    text: paragraphs(
      "Hello all,",
      "the art room has new supplies. You can pick up sketchbooks and pencils from me during the break.",
      "Please handle the materials carefully and return them clean. Lost items must be paid for.",
      "I am looking forward to your new projects.",
      "Kind regards,\nMs. Lang",
    ),
    author: "Ms. Lang", recipient: "Class 8A", type: "chat", type_label: "Chat", additional_data: {}, is_starred: false, is_done: false, done_at: "", reaction_count: 3, created_at: "2026-10-08T13:00:00", is_removed: false,
  },
  {
    id: 4126, timestamp: "2026-10-09 10:45:00", timestamp_iso: "2026-10-09T10:45:00", sort_key: "2026-10-09T10:45:00",
    text: paragraphs(
      "Dear Class 8A,",
      "the English listening test will take place next Thursday. Please practise the audio files from the online platform.",
      "The test lasts 30 minutes and includes short dialogues and a longer text. You may take notes during the listening.",
      "Review the vocabulary from Units 1 to 4. Good preparation makes a big difference.",
      "Kind regards,\nMr. Meyer",
    ),
    author: "Mr. Meyer", recipient: "Class 8A", type: "news", type_label: "News", additional_data: {}, is_starred: false, is_done: false, done_at: "", reaction_count: 5, created_at: "2026-10-09T10:45:00", is_removed: false,
  },
  {
    id: 4127, timestamp: "2026-10-10 09:00:00", timestamp_iso: "2026-10-10T09:00:00", sort_key: "2026-10-10T09:00:00",
    text: paragraphs(
      "Hello everyone,",
      "the school library now offers a reading challenge. Read three books this term and earn a certificate.",
      "You can choose any genre and level. Please log your books in the library notebook.",
      "The challenge ends in December. Good luck to all readers.",
      "Student council",
    ),
    author: "Student council", recipient: "Class 8A", type: "sprava", type_label: "Message", additional_data: {}, is_starred: false, is_done: false, done_at: "", reaction_count: 7, created_at: "2026-10-10T09:00:00", is_removed: false,
  },
  {
    id: 4128, timestamp: "2027-03-15 10:30:00", timestamp_iso: "2027-03-15T10:30:00", sort_key: "2027-03-15T10:30:00",
    text: paragraphs(
      "Dear Class 8A,",
      "the spring term project will focus on sustainability. Each group will research a topic and present solutions for our school.",
      "Topics include energy saving, waste reduction and green spaces. Please form groups of four and register your topic by Friday.",
      "We will have regular check-ins and a final presentation in May. I am excited to see your ideas.",
      "Kind regards,\nMr. Özdemir",
    ),
    author: "Mr. Özdemir", recipient: "Class 8A", type: "news", type_label: "News", additional_data: {}, is_starred: false, is_done: false, done_at: "", reaction_count: 4, created_at: "2027-03-15T10:30:00", is_removed: false,
  },
  {
    id: 4129, timestamp: "2027-09-20 08:45:00", timestamp_iso: "2027-09-20T08:45:00", sort_key: "2027-09-20T08:45:00",
    text: paragraphs(
      "Dear Class 8A,",
      "welcome back to the new school year. I hope you had a good summer and are ready for new challenges.",
      "Our first topic will be renewable energy. Please bring your materials from last year, especially your notes on physics and chemistry.",
      "We will also start a new reading project. Choose a book from the list I will hand out on Monday.",
      "I look forward to working with you again.",
      "Kind regards,\nMs. Berger",
    ),
    author: "Ms. Berger", recipient: "Class 8A", type: "sprava", type_label: "Message", additional_data: {}, is_starred: false, is_done: false, done_at: "", reaction_count: 8, created_at: "2027-09-20T08:45:00", is_removed: false,
  },
  {
    id: 4130, timestamp: "2028-03-01 09:00:00", timestamp_iso: "2028-03-01T09:00:00", sort_key: "2028-03-01T09:00:00",
    text: paragraphs(
      "Dear Class 8A,",
      "as we approach the end of our time together, I want to thank you for your hard work and dedication.",
      "The final exams will take place in May and June. Please review all units and ask questions early.",
      "We will also have a small farewell celebration in July. More details will follow.",
      "I am proud of everything you have achieved.",
      "Kind regards,\nMs. Berger",
    ),
    author: "Ms. Berger", recipient: "Class 8A", type: "sprava", type_label: "Message", additional_data: {}, is_starred: true, is_done: false, done_at: "", reaction_count: 12, created_at: "2028-03-01T09:00:00", is_removed: false,
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
  { id: 5106, type: "homework", title: "Fractions: common denominator", subject: "Math", teacher: "Ms. Berger", description: "Exercises 1–12 on page 38.", assigned: due(-3), assigned_iso: due(-3), due: due(2), due_display: new Date(`${due(2)}T12:00:00`).toLocaleDateString("en-US"), status: "offen", is_done: false, is_hidden: false },
  { id: 5107, type: "homework", title: "Read chapter 7", subject: "German", teacher: "Mr. Özdemir", description: "Answer the questions at the end.", assigned: due(-5), assigned_iso: due(-5), due: due(-2), due_display: new Date(`${due(-2)}T12:00:00`).toLocaleDateString("en-US"), status: "überfällig", is_done: false, is_hidden: false },
  { id: 5108, type: "homework", title: "Vocabulary set 4", subject: "English", teacher: "Mr. Meyer", description: "Words 26–50, include example sentences.", assigned: due(-2), assigned_iso: due(-2), due: due(3), due_display: new Date(`${due(3)}T12:00:00`).toLocaleDateString("en-US"), status: "offen", is_done: false, is_hidden: false },
  { id: 5109, type: "homework", title: "Poster draft final", subject: "Art", teacher: "Ms. Lang", description: "Colour version with bibliography.", assigned: due(-6), assigned_iso: due(-6), due: due(-4), due_display: new Date(`${due(-4)}T12:00:00`).toLocaleDateString("en-US"), status: "erledigt", is_done: true, is_hidden: false },
  { id: 5110, type: "homework", title: "History timeline", subject: "History", teacher: "Mr. Kowalski", description: "Events from 1789 to 1914.", assigned: due(-7), assigned_iso: due(-7), due: due(-1), due_display: new Date(`${due(-1)}T12:00:00`).toLocaleDateString("en-US"), status: "überfällig", is_done: false, is_hidden: false },
  { id: 5111, type: "homework", title: "Physics: forces summary", subject: "Physics", teacher: "Ms. Berger", description: "One page, hand-written.", assigned: due(-1), assigned_iso: due(-1), due: due(5), due_display: new Date(`${due(5)}T12:00:00`).toLocaleDateString("en-US"), status: "offen", is_done: false, is_hidden: false },
  { id: 5112, type: "homework", title: "Chemistry: acids and bases", subject: "Chemistry", teacher: "Mr. Özdemir", description: "Read the chapter and answer questions 1–8.", assigned: due(-2), assigned_iso: due(-2), due: due(0), due_display: new Date(`${due(0)}T12:00:00`).toLocaleDateString("en-US"), status: "heute fällig", is_done: false, is_hidden: false },
  { id: 5113, type: "homework", title: "English essay", subject: "English", teacher: "Mr. Meyer", description: "200 words about your favourite book.", assigned: due(-4), assigned_iso: due(-4), due: due(6), due_display: new Date(`${due(6)}T12:00:00`).toLocaleDateString("en-US"), status: "offen", is_done: false, is_hidden: false },
  { id: 5114, type: "homework", title: "Math: word problems", subject: "Math", teacher: "Ms. Berger", description: "Problems 1–5, show all steps.", assigned: due(-3), assigned_iso: due(-3), due: due(1), due_display: new Date(`${due(1)}T12:00:00`).toLocaleDateString("en-US"), status: "offen", is_done: false, is_hidden: false },
  { id: 5115, type: "homework", title: "German: letter writing", subject: "German", teacher: "Mr. Özdemir", description: "Formal letter to the school office.", assigned: due(-8), assigned_iso: due(-8), due: due(-5), due_display: new Date(`${due(-5)}T12:00:00`).toLocaleDateString("en-US"), status: "erledigt", is_done: true, is_hidden: false },
  { id: 5116, type: "homework", title: "Art: colour wheel", subject: "Art", teacher: "Ms. Lang", description: "Paint primary and secondary colours.", assigned: due(-1), assigned_iso: due(-1), due: due(4), due_display: new Date(`${due(4)}T12:00:00`).toLocaleDateString("en-US"), status: "offen", is_done: false, is_hidden: false },
  { id: 5117, type: "homework", title: "History: French Revolution", subject: "History", teacher: "Mr. Kowalski", description: "Summary of the key events.", assigned: due(-2), assigned_iso: due(-2), due: due(2), due_display: new Date(`${due(2)}T12:00:00`).toLocaleDateString("en-US"), status: "offen", is_done: false, is_hidden: false },
  { id: 5118, type: "homework", title: "Physics: energy forms", subject: "Physics", teacher: "Ms. Berger", description: "List and explain five forms of energy.", assigned: due(-5), assigned_iso: due(-5), due: due(-3), due_display: new Date(`${due(-3)}T12:00:00`).toLocaleDateString("en-US"), status: "überfällig", is_done: false, is_hidden: false },
  { id: 5119, type: "sexam", title: "Oral exam: reading aloud", subject: "German", teacher: "Mr. Özdemir", description: "Prepare a text of your choice.", assigned: due(-4), assigned_iso: due(-4), due: due(7), due_display: new Date(`${due(7)}T12:00:00`).toLocaleDateString("en-US"), status: "offen", is_done: false, is_hidden: false },
  { id: 5120, type: "homework", title: "English: dialogue", subject: "English", teacher: "Mr. Meyer", description: "Write a short dialogue at the restaurant.", assigned: due(-1), assigned_iso: due(-1), due: due(3), due_display: new Date(`${due(3)}T12:00:00`).toLocaleDateString("en-US"), status: "offen", is_done: false, is_hidden: false },
  { id: 5121, type: "homework", title: "Math: equations", subject: "Math", teacher: "Ms. Berger", description: "Solve linear equations 1-10.", assigned: due(-2), assigned_iso: due(-2), due: due(3), due_display: new Date(`${due(3)}T12:00:00`).toLocaleDateString("en-US"), status: "offen", is_done: false, is_hidden: false },
  { id: 5122, type: "homework", title: "German: book report", subject: "German", teacher: "Mr. Özdemir", description: "Write a report on the novel.", assigned: due(-4), assigned_iso: due(-4), due: due(-1), due_display: new Date(`${due(-1)}T12:00:00`).toLocaleDateString("en-US"), status: "überfällig", is_done: false, is_hidden: false },
  { id: 5123, type: "homework", title: "English: presentation prep", subject: "English", teacher: "Mr. Meyer", description: "Prepare slides for the talk.", assigned: due(-1), assigned_iso: due(-1), due: due(5), due_display: new Date(`${due(5)}T12:00:00`).toLocaleDateString("en-US"), status: "offen", is_done: false, is_hidden: false },
  { id: 5124, type: "homework", title: "Art: sculpture", subject: "Art", teacher: "Ms. Lang", description: "Model a small figure.", assigned: due(-6), assigned_iso: due(-6), due: due(-2), due_display: new Date(`${due(-2)}T12:00:00`).toLocaleDateString("en-US"), status: "erledigt", is_done: true, is_hidden: false },
  { id: 5125, type: "homework", title: "History: essay", subject: "History", teacher: "Mr. Kowalski", description: "Write about the Industrial Revolution.", assigned: due(-3), assigned_iso: due(-3), due: due(2), due_display: new Date(`${due(2)}T12:00:00`).toLocaleDateString("en-US"), status: "offen", is_done: false, is_hidden: false },
];

export const demoGrades = [
  { id: 6101, title: "Written test 1", subject: "Math", teacher: "Ms. Berger", date_display: "09/24/2026", date_iso: "2026-09-24", sort_key: "2026-09-24T00:00:00", comment: "", grade_display: "2", grade_num: 2, weight: 1, weight_display: "", grade_sub: "", badge: "g12", class_avg: 2.4, class_avg_display: "2.4", is_classic: true },
  { id: 6102, title: "Vocabulary quiz 3", subject: "English", teacher: "Mr. Meyer", date_display: "09/22/2026", date_iso: "2026-09-22", sort_key: "2026-09-22T00:00:00", comment: "", grade_display: "1", grade_num: 1, weight: 1, weight_display: "", grade_sub: "", badge: "g12", class_avg: null, class_avg_display: "", is_classic: true },
  { id: 6103, title: "Literary analysis", subject: "German", teacher: "Mr. Özdemir", date_display: "09/18/2026", date_iso: "2026-09-18", sort_key: "2026-09-18T00:00:00", comment: "Good evidence", grade_display: "2+", grade_num: 1.7, weight: 0.5, weight_display: "½", grade_sub: "", badge: "g12", class_avg: 2.8, class_avg_display: "2.8", is_classic: true },
  { id: 6104, title: "Fractions test", subject: "Math", teacher: "Ms. Berger", date_display: "10/02/2026", date_iso: "2026-10-02", sort_key: "2026-10-02T00:00:00", comment: "Careful with signs", grade_display: "2-", grade_num: 2.3, weight: 1, weight_display: "", grade_sub: "", badge: "g12", class_avg: 2.7, class_avg_display: "2.7", is_classic: true },
  { id: 6105, title: "Grammar quiz", subject: "English", teacher: "Mr. Meyer", date_display: "10/05/2026", date_iso: "2026-10-05", sort_key: "2026-10-05T00:00:00", comment: "", grade_display: "1-", grade_num: 1.3, weight: 0.5, weight_display: "½", grade_sub: "", badge: "g12", class_avg: 2.1, class_avg_display: "2.1", is_classic: true },
  { id: 6106, title: "Essay: my holidays", subject: "German", teacher: "Mr. Özdemir", date_display: "10/08/2026", date_iso: "2026-10-08", sort_key: "2026-10-08T00:00:00", comment: "Good structure", grade_display: "2", grade_num: 2, weight: 1, weight_display: "", grade_sub: "", badge: "g12", class_avg: 2.5, class_avg_display: "2.5", is_classic: true },
  { id: 6107, title: "Poster project", subject: "Art", teacher: "Ms. Lang", date_display: "10/12/2026", date_iso: "2026-10-12", sort_key: "2026-10-12T00:00:00", comment: "Creative idea", grade_display: "1+", grade_num: 1.2, weight: 2, weight_display: "2", grade_sub: "", badge: "g12", class_avg: 1.8, class_avg_display: "1.8", is_classic: true },
  { id: 6108, title: "History test", subject: "History", teacher: "Mr. Kowalski", date_display: "10/15/2026", date_iso: "2026-10-15", sort_key: "2026-10-15T00:00:00", comment: "", grade_display: "3", grade_num: 3, weight: 1, weight_display: "", grade_sub: "", badge: "g12", class_avg: 2.9, class_avg_display: "2.9", is_classic: true },
  { id: 6109, title: "Physics: forces", subject: "Physics", teacher: "Ms. Berger", date_display: "10/20/2026", date_iso: "2026-10-20", sort_key: "2026-10-20T00:00:00", comment: "Review units", grade_display: "2+", grade_num: 1.7, weight: 1, weight_display: "", grade_sub: "", badge: "g12", class_avg: 2.6, class_avg_display: "2.6", is_classic: true },
  { id: 6110, title: "Chemistry quiz", subject: "Chemistry", teacher: "Mr. Özdemir", date_display: "11/03/2026", date_iso: "2026-11-03", sort_key: "2026-11-03T00:00:00", comment: "", grade_display: "2", grade_num: 2, weight: 0.5, weight_display: "½", grade_sub: "", badge: "g12", class_avg: 2.4, class_avg_display: "2.4", is_classic: true },
  { id: 6111, title: "Math: geometry", subject: "Math", teacher: "Ms. Berger", date_display: "11/10/2026", date_iso: "2026-11-10", sort_key: "2026-11-10T00:00:00", comment: "Good drawings", grade_display: "1", grade_num: 1, weight: 1, weight_display: "", grade_sub: "", badge: "g12", class_avg: 2.2, class_avg_display: "2.2", is_classic: true },
  { id: 6112, title: "English: presentation", subject: "English", teacher: "Mr. Meyer", date_display: "11/18/2026", date_iso: "2026-11-18", sort_key: "2026-11-18T00:00:00", comment: "Fluent", grade_display: "1+", grade_num: 1.2, weight: 2, weight_display: "2", grade_sub: "", badge: "g12", class_avg: 1.9, class_avg_display: "1.9", is_classic: true },
  { id: 6113, title: "German: poetry", subject: "German", teacher: "Mr. Özdemir", date_display: "12/02/2026", date_iso: "2026-12-02", sort_key: "2026-12-02T00:00:00", comment: "", grade_display: "2+", grade_num: 1.7, weight: 1, weight_display: "", grade_sub: "", badge: "g12", class_avg: 2.6, class_avg_display: "2.6", is_classic: true },
  { id: 6114, title: "Art: colour theory", subject: "Art", teacher: "Ms. Lang", date_display: "01/12/2027", date_iso: "2027-01-12", sort_key: "2027-01-12T00:00:00", comment: "Well mixed", grade_display: "1", grade_num: 1, weight: 1, weight_display: "", grade_sub: "", badge: "g12", class_avg: 1.7, class_avg_display: "1.7", is_classic: true },
  { id: 6115, title: "Math: algebra", subject: "Math", teacher: "Ms. Berger", date_display: "02/05/2027", date_iso: "2027-02-05", sort_key: "2027-02-05T00:00:00", comment: "", grade_display: "2", grade_num: 2, weight: 1, weight_display: "", grade_sub: "", badge: "g12", class_avg: 2.5, class_avg_display: "2.5", is_classic: true },
  { id: 6116, title: "English: listening", subject: "English", teacher: "Mr. Meyer", date_display: "03/10/2027", date_iso: "2027-03-10", sort_key: "2027-03-10T00:00:00", comment: "Good comprehension", grade_display: "1-", grade_num: 1.3, weight: 1, weight_display: "", grade_sub: "", badge: "g12", class_avg: 2.0, class_avg_display: "2.0", is_classic: true },
  { id: 6117, title: "German: novel", subject: "German", teacher: "Mr. Özdemir", date_display: "04/15/2027", date_iso: "2027-04-15", sort_key: "2027-04-15T00:00:00", comment: "Insightful", grade_display: "1+", grade_num: 1.2, weight: 2, weight_display: "2", grade_sub: "", badge: "g12", class_avg: 2.1, class_avg_display: "2.1", is_classic: true },
  { id: 6118, title: "Physics: electricity", subject: "Physics", teacher: "Ms. Berger", date_display: "05/20/2027", date_iso: "2027-05-20", sort_key: "2027-05-20T00:00:00", comment: "", grade_display: "2+", grade_num: 1.7, weight: 1, weight_display: "", grade_sub: "", badge: "g12", class_avg: 2.4, class_avg_display: "2.4", is_classic: true },
  { id: 6119, title: "History: 20th century", subject: "History", teacher: "Mr. Kowalski", date_display: "06/15/2027", date_iso: "2027-06-15", sort_key: "2027-06-15T00:00:00", comment: "Good overview", grade_display: "2", grade_num: 2, weight: 1, weight_display: "", grade_sub: "", badge: "g12", class_avg: 2.7, class_avg_display: "2.7", is_classic: true },
  { id: 6120, title: "Math: final exam", subject: "Math", teacher: "Ms. Berger", date_display: "02/28/2028", date_iso: "2028-02-28", sort_key: "2028-02-28T00:00:00", comment: "Excellent", grade_display: "1", grade_num: 1, weight: 3, weight_display: "3", grade_sub: "", badge: "g12", class_avg: 2.0, class_avg_display: "2.0", is_classic: true },
  { id: 6121, title: "Math: equations", subject: "Math", teacher: "Ms. Berger", date_display: "03/15/2028", date_iso: "2028-03-15", sort_key: "2028-03-15T00:00:00", comment: "Good work", grade_display: "2", grade_num: 2, weight: 1, weight_display: "", grade_sub: "", badge: "g12", class_avg: 2.3, class_avg_display: "2.3", is_classic: true },
  { id: 6122, title: "German: essay", subject: "German", teacher: "Mr. Özdemir", date_display: "04/10/2028", date_iso: "2028-04-10", sort_key: "2028-04-10T00:00:00", comment: "", grade_display: "1+", grade_num: 1.2, weight: 1, weight_display: "", grade_sub: "", badge: "g12", class_avg: 2.0, class_avg_display: "2.0", is_classic: true },
  { id: 6123, title: "English: final", subject: "English", teacher: "Mr. Meyer", date_display: "05/05/2028", date_iso: "2028-05-05", sort_key: "2028-05-05T00:00:00", comment: "Fluent", grade_display: "1", grade_num: 1, weight: 2, weight_display: "2", grade_sub: "", badge: "g12", class_avg: 1.8, class_avg_display: "1.8", is_classic: true },
  { id: 6124, title: "Art: final project", subject: "Art", teacher: "Ms. Lang", date_display: "05/20/2028", date_iso: "2028-05-20", sort_key: "2028-05-20T00:00:00", comment: "Excellent", grade_display: "1+", grade_num: 1.2, weight: 2, weight_display: "2", grade_sub: "", badge: "g12", class_avg: 1.6, class_avg_display: "1.6", is_classic: true },
  { id: 6125, title: "History: final", subject: "History", teacher: "Mr. Kowalski", date_display: "06/01/2028", date_iso: "2028-06-01", sort_key: "2028-06-01T00:00:00", comment: "Good overview", grade_display: "2", grade_num: 2, weight: 1, weight_display: "", grade_sub: "", badge: "g12", class_avg: 2.5, class_avg_display: "2.5", is_classic: true },
];

export const demoLessons = [
  { period: "1", time: "07:45–08:30", title: "Math", is_lernzeit: false, teachers: "Ms. Berger", rooms: "R204", is_cancelled: false, is_event: false, is_online: false },
  { period: "2–3", time: "08:35–10:20", title: "Study hall", is_lernzeit: true, teachers: "", rooms: "Study room", is_cancelled: false, is_event: false, is_online: false },
  { period: "4", time: "10:25–11:10", title: "English", is_lernzeit: false, teachers: "Mr. Meyer", rooms: "R108", is_cancelled: true, is_event: false, is_online: false },
  { period: "5", time: "11:15–12:00", title: "Physics", is_lernzeit: false, teachers: "Ms. Berger", rooms: "R305", is_cancelled: false, is_event: false, is_online: true },
  { period: "6", time: "12:05–12:50", title: "History", is_lernzeit: false, teachers: "Mr. Kowalski", rooms: "R112", is_cancelled: false, is_event: false, is_online: false },
  { period: "7–8", time: "12:55–14:30", title: "Art", is_lernzeit: false, teachers: "Ms. Lang", rooms: "M101", is_cancelled: false, is_event: false, is_online: false },
  { period: "9", time: "14:35–15:20", title: "Chemistry", is_lernzeit: false, teachers: "Mr. Özdemir", rooms: "Lab 2", is_cancelled: false, is_event: false, is_online: false },
  { period: "10", time: "15:25–16:10", title: "German", is_lernzeit: false, teachers: "Mr. Özdemir", rooms: "R210", is_cancelled: false, is_event: false, is_online: false },
  { period: "11", time: "16:15–17:00", title: "Study hall", is_lernzeit: true, teachers: "", rooms: "Study room", is_cancelled: false, is_event: false, is_online: false },
  { period: "12", time: "17:05–17:50", title: "Math clinic", is_lernzeit: false, teachers: "Ms. Berger", rooms: "R204", is_cancelled: false, is_event: false, is_online: false },
];

/**
 * Empfängerliste der Demo: dieselben IDs, die der echte Provider aus den
 * dbi-Schlüsseln bildet (`Teacher<key>` / `Student<key>`). Innerhalb der
 * Gruppen alphabetisch nach `name.toLowerCase()`, wie `recipientsFromDbi` –
 * dort wird allerdings über alle Gruppen hinweg sortiert, hier stehen die
 * Lehrkräfte im Verfassen-Dialog vorne.
 *
 * Alle Lehrkräfte, die in `demoHomework`, `demoGrades` oder `demoLessons`
 * auftauchen, stehen auch hier, damit man ihnen im Verfassen-Dialog schreiben
 * kann. `detail` trägt das Fach bzw. die Klasse.
 */
export const demoRecipients = [
  { id: "Teacher9", name: "Mr. Kowalski", kind: "teacher", detail: "History" },
  { id: "Teacher10", name: "Mr. Meyer", kind: "teacher", detail: "English" },
  { id: "Teacher8", name: "Mr. Özdemir", kind: "teacher", detail: "German" },
  { id: "Teacher7", name: "Ms. Berger", kind: "teacher", detail: "Math, Physics" },
  { id: "Teacher11", name: "Ms. Lang", kind: "teacher", detail: "Art" },
  { id: "Student9", name: "David Example", kind: "student", detail: "8A" },
  { id: "Student10", name: "Elias Example", kind: "student", detail: "8A" },
  { id: "Student11", name: "Jonas Example", kind: "student", detail: "8A" },
  { id: "Student12", name: "Lea Example", kind: "student", detail: "8A" },
  { id: "Student13", name: "Miriam Example", kind: "student", detail: "8A" },
  { id: "Student14", name: "Sofia Example", kind: "student", detail: "8A" },
];
