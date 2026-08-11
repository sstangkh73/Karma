-- Central note sheet registry.
--
-- To add a new sheet:
-- 1. Copy one block below.
-- 2. Change `id` to the NoteId you will put on the note Part in Studio.
-- 3. Write `title.th` and `body.th` first; Thai is the source meaning.
-- 4. Add every supported language from that Thai source:
--    th, en, zh-cn, es, pt-br, fr, de, ru, ko, id.
-- 5. Keep names in English transliteration in every language, for example `Win`.
-- 6. Keep Buddhist/moral weight terms such as บาป/กรรม as `KARMA`.
-- 7. Choose one view type:
--    `text` uses localized title/body in the normal reader.
--    `image` uses image/imageAspectRatio in the zoomable image viewer.

return {
	{
		id = "note_0",
		viewType = "text",
		title = {
			th = "บันทึกทดสอบระบบ",
			en = "System Test Note",
			["zh-cn"] = "系统测试纸条",
			es = "Nota de prueba del sistema",
			["pt-br"] = "Nota de teste do sistema",
			fr = "Note de test systeme",
			de = "System-Testnotiz",
			ru = "Тестовая записка системы",
			ko = "시스템 테스트 쪽지",
			id = "Catatan Tes Sistem",
		},
		body = {
			th = [[สวัสดี ผู้ที่พบจดหมายฉบับนี้

ฉันเขียนข้อความนี้เพื่อบอกเล่าสิ่งที่เกิดขึ้น
ในวันที่ทุกอย่างเปลี่ยนไป...

หากคุณอ่านสิ่งนี้ แสดงว่าคุณพบกระดาษแล้ว
โปรดจำไว้ว่าทุกอย่างไม่ได้เป็นอย่างที่เห็น

- ผู้เขียน]],
			en = [[Hello to whoever finds this letter.

I am writing this message to tell you what happened
on the day everything changed...

If you are reading this, then you have already found the paper.
Please remember that not everything is as it seems.

- The Writer]],
			["zh-cn"] = [[致找到这封信的人：

我写下这段话，是想告诉你那一天发生了什么，
那一天，一切都改变了……

如果你正在读这封信，说明你已经找到那张纸了。
请记住，事情并不总是表面看起来的那样。

- 写信人]],
			es = [[Hola a quien encuentre esta carta.

Escribo este mensaje para contarte lo que paso
el dia en que todo cambio...

Si estas leyendo esto, entonces ya encontraste el papel.
Por favor, recuerda que no todo es lo que parece.

- El Autor]],
			["pt-br"] = [[Ola a quem encontrar esta carta.

Estou escrevendo esta mensagem para contar o que aconteceu
no dia em que tudo mudou...

Se voce esta lendo isto, entao ja encontrou o papel.
Por favor, lembre-se de que nem tudo e o que parece.

- O Autor]],
			fr = [[Bonjour a la personne qui trouvera cette lettre.

J'ecris ce message pour te raconter ce qui s'est passe
le jour ou tout a change...

Si tu lis ceci, c'est que tu as deja trouve la feuille.
N'oublie pas que tout n'est pas toujours ce qu'il semble etre.

- L'Auteur]],
			de = [[Hallo an die Person, die diesen Brief findet.

Ich schreibe diese Nachricht, um dir zu erzahlen, was an dem Tag geschah,
an dem sich alles veranderte...

Wenn du das hier liest, hast du das Papier bereits gefunden.
Bitte denke daran, dass nicht alles so ist, wie es scheint.

- Der Verfasser]],
			ru = [[Здравствуйте, тот, кто найдёт это письмо.

Я пишу это сообщение, чтобы рассказать тебе, что произошло
в тот день, когда всё изменилось...

Если ты читаешь это, значит, ты уже нашёл этот лист.
Пожалуйста, помни: не всё является тем, чем кажется.

- Автор]],
			ko = [[이 편지를 발견한 사람에게.

모든 것이 바뀌던 날에 무슨 일이 있었는지
당신에게 전하기 위해 이 글을 남깁니다...

이 글을 읽고 있다면, 당신은 이미 그 종이를 찾은 것입니다.
보이는 것이 전부는 아니라는 사실을 꼭 기억해 주세요.

- 작성자]],
			id = [[Halo untuk siapa pun yang menemukan surat ini.

Aku menulis pesan ini untuk memberitahumu apa yang terjadi
pada hari ketika semuanya berubah...

Jika kamu membaca ini, berarti kamu sudah menemukan kertas itu.
Tolong ingat bahwa tidak semua hal seperti yang terlihat.

- Penulis]],
		},
		titleKey = "notes.note_0.title",
		typedTextKey = "notes.note_0.body",
		handwritingImage = "rbxassetid://0",
	},
	{
		id = "note_1",
		viewType = "text",
		title = {
			th = "จดหมายสำหรับ 'คน'",
			en = "Letter for a Person",
			["zh-cn"] = "给“那个人”的信",
			es = "Carta para una persona",
			["pt-br"] = "Carta para uma pessoa",
			fr = "Lettre pour quelqu'un",
			de = "Brief fur eine Person",
			ru = "Письмо для одного человека",
			ko = "어떤 사람에게 보내는 편지",
			id = "Surat untuk Seseorang",
		},
		body = {
			th = [[วิน

ว่าแล้วนายต้องมา

KARMA ของนายมันอยู่ตรงนั้นแหละ ที่ที่นายปิดมันเอาไว้

-สักคน]],
			en = [[Win,

I knew you would come.

Your KARMA is right there, in the place where you buried it.

- From Kru Fa]],
			["zh-cn"] = [[Win，

我就知道你会来。

你的 KARMA 就在那里，在你亲手把它藏起来的地方。

- Kru Fa]],
			es = [[Win,

Sabia que vendrias.

Tu KARMA esta justo alli, en el lugar donde lo enterraste.

- De Kru Fa]],
			["pt-br"] = [[Win,

Eu sabia que voce viria.

O seu KARMA esta bem ali, no lugar onde voce o enterrou.

- De Kru Fa]],
			fr = [[Win,

Je savais que tu viendrais.

Ton KARMA est juste la, a l'endroit ou tu l'as enterre.

- De Kru Fa]],
			de = [[Win,

Ich wusste, dass du kommen wurdest.

Dein KARMA liegt genau dort, an dem Ort, an dem du es begraben hast.

- Von Kru Fa]],
			ru = [[Win,

Я знала, что ты придёшь.

Твоя KARMA прямо там, в месте, где ты её закопал.

- От Kru Fa]],
			ko = [[Win,

네가 올 줄 알았어.

네 KARMA는 바로 거기에 있어. 네가 그것을 묻어 둔 곳에.

- Kru Fa]],
			id = [[Win,

Aku tahu kamu akan datang.

KARMA kamu ada tepat di sana, di tempat kamu menguburnya.

- Dari Kru Fa]],
		},
		titleKey = "notes.note_1.title",
		typedTextKey = "notes.note_1.body",
		handwritingImage = "rbxassetid://94019106857716",
	},
	{
		id = "note_2",
		viewType = "text",
		title = {
			th = "จดหมายถึง วิน",
			en = "Letter to Win",
			["zh-cn"] = "给 Win 的信",
			es = "Carta para Win",
			["pt-br"] = "Carta para Win",
			fr = "Lettre a Win",
			de = "Brief an Win",
			ru = "Письмо Win",
			ko = "Win에게 보내는 편지",
			id = "Surat untuk Win",
		},
		body = {
			th = [[ของอยู่ที่โต๊ะครู ที่ตึกใหม่

- จากครูฟ้า]],
			en = [[The thing is on the teacher's desk in the new building.

- From Teacher Fa]],
			["zh-cn"] = [[东西在新楼的老师桌上。

- Teacher Fa]],
			es = [[La cosa esta en el escritorio del profesor, en el edificio nuevo.

- De Teacher Fa]],
			["pt-br"] = [[A coisa esta na mesa do professor, no predio novo.

- De Teacher Fa]],
			fr = [[L'objet est sur le bureau du professeur, dans le nouveau batiment.

- De Teacher Fa]],
			de = [[Das Ding liegt auf dem Lehrertisch im neuen Gebaude.

- Von Teacher Fa]],
			ru = [[Вещь лежит на столе учителя в новом здании.

- От Teacher Fa]],
			ko = [[그 물건은 새 건물의 교사 책상 위에 있어.

- Teacher Fa]],
			id = [[Barangnya ada di meja guru, di gedung baru.

- Dari Teacher Fa]],
		},
		titleKey = "notes.note_2.title",
		typedTextKey = "notes.note_2.body",
		handwritingImage = "rbxassetid://127081649027507",
	},
	{
		id = "note_3",
		viewType = "text",
		title = {
			th = "ทางที่ซ่อนอยู่",
			en = "The Hidden Path",
			["zh-cn"] = "隐藏的路",
			es = "El camino oculto",
			["pt-br"] = "O caminho oculto",
			fr = "Le chemin cache",
			de = "Der verborgene Weg",
			ru = "Скрытый путь",
			ko = "숨겨진 길",
			id = "Jalan Tersembunyi",
		},
		body = {
			th = [[ไม่ใช่ทุกก้าวที่มุ่งไปข้างหน้า
จะพาเราเข้าใกล้จุดหมาย

บางครั้ง สิ่งที่ดูเหมือนการถอยหลัง
อาจเป็นก้าวเดียว
ที่พาเราไปต่อ]],
			en = [[Not every step forward
brings us closer to our destination.

Sometimes, what seems like a step backward
may be the only step
that lets us move on.]],
			["zh-cn"] = [[并非每一步向前，
都会让我们更接近终点。

有时，看似后退的一步，
反而可能是唯一
能让我们继续前行的一步。]],
			es = [[No todos los pasos hacia delante
nos acercan a nuestro destino.

A veces, lo que parece un paso atras
puede ser el unico paso
que nos permite continuar.]],
			["pt-br"] = [[Nem todo passo a frente
nos aproxima do destino.

As vezes, o que parece um passo para tras
pode ser o unico passo
que nos permite continuar.]],
			fr = [[Chaque pas en avant
ne nous rapproche pas forcement de notre destination.

Parfois, ce qui ressemble a un pas en arriere
est peut-etre le seul pas
qui nous permet de continuer.]],
			de = [[Nicht jeder Schritt nach vorn
bringt uns unserem Ziel naher.

Manchmal ist das, was wie ein Schritt zuruck aussieht,
vielleicht der einzige Schritt,
der uns weitergehen lasst.]],
			ru = [[Не каждый шаг вперёд
приближает нас к цели.

Иногда то, что кажется шагом назад,
может оказаться единственным шагом,
который позволит двигаться дальше.]],
			ko = [[앞으로 내딛는 모든 걸음이
목적지에 가까워지게 하는 것은 아니다.

때로는 뒤로 물러나는 듯한 한 걸음이
우리를 계속 나아가게 하는
유일한 걸음일 수 있다.]],
			id = [[Tidak setiap langkah ke depan
membawa kita lebih dekat ke tujuan.

Terkadang, sesuatu yang tampak seperti langkah mundur
mungkin merupakan satu-satunya langkah
yang membuat kita dapat melanjutkan perjalanan.]],
		},
		titleKey = "notes.note_3.title",
		typedTextKey = "notes.note_3.body",
		handwritingImage = "rbxassetid://118635730873338",
	},
	{
		id = "note_4",
		title = {
			th = "ข่าวเมตตาวิทยา",
			en = "Metta Wittaya News",
			["zh-cn"] = "Metta Wittaya 校报",
			es = "Noticias de Metta Wittaya",
			["pt-br"] = "Noticias de Metta Wittaya",
			fr = "Actualites de Metta Wittaya",
			de = "Metta Wittaya Nachrichten",
			ru = "Новости Metta Wittaya",
			ko = "Metta Wittaya 소식",
			id = "Berita Metta Wittaya",
		},
		body = {
			th = "ชฎาคู่คืนสู่แท่นเดิม",
			en = "The pair of chada returns to its original stand.",
			["zh-cn"] = "成对的 chada 回到了原来的展台。",
			es = "El par de chada vuelve a su altar original.",
			["pt-br"] = "O par de chada retorna ao suporte original.",
			fr = "La paire de chada retrouve son presentoir d'origine.",
			de = "Das Chada-Paar kehrt auf seinen ursprunglichen Stand zuruck.",
			ru = "Пара chada возвращается на прежнюю подставку.",
			ko = "한 쌍의 chada가 원래 진열대로 돌아왔다.",
			id = "Sepasang chada kembali ke tempat pajangan semula.",
		},
		viewType = "image",
		image = "rbxassetid://135936162829416",
		imageAspectRatio = 2 / 3,
	},
	{
		id = "note_5",
		viewType = "image",
		title = {
			th = "แฟ้มหลักฐานการก่อสร้าง",
			en = "Construction Evidence File",
			["zh-cn"] = "建筑证据档案",
			es = "Expediente de pruebas de construccion",
			["pt-br"] = "Arquivo de provas da construcao",
			fr = "Dossier de preuves de construction",
			de = "Bau-Beweisakte",
			ru = "Досье строительных доказательств",
			ko = "건설 증거 파일",
			id = "Berkas Bukti Konstruksi",
		},
		body = {
			th = "ใบตรวจรับและสำเนาใบส่งมอบวัสดุ",
			en = "Final inspection certificate and material delivery copy.",
			["zh-cn"] = "最终验收证明和材料交付单副本。",
			es = "Certificado de inspeccion final y copia de entrega de materiales.",
			["pt-br"] = "Certificado de inspecao final e copia da entrega de materiais.",
			fr = "Certificat d'inspection finale et copie de livraison des materiaux.",
			de = "Abnahmebescheinigung und Kopie des Materiallieferscheins.",
			ru = "Акт окончательной приёмки и копия поставки материалов.",
			ko = "최종 검수 증명서와 자재 납품서 사본.",
			id = "Sertifikat pemeriksaan akhir dan salinan pengiriman bahan.",
		},
		image = "rbxassetid://114904176726241",
		imageAspectRatio = 943 / 1664,
	},
}
