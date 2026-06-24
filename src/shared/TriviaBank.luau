--!strict
-- TriviaBank: World Cup football trivia, tagged by difficulty (easy/medium/hard).
-- TriviaService (the duel) picks a daily rotating set; the Trivia Gauntlet pulls by
-- difficulty so the course ramps from easy questions early to hard ones late.

local TriviaBank = {}

export type Difficulty = "easy" | "medium" | "hard"

export type Question = {
	q: string,
	options: { A: string, B: string, C: string, D: string },
	answer: "A" | "B" | "C" | "D",
	difficulty: Difficulty,
}

TriviaBank.Questions = {
	-- ===================== EASY =====================
	{ q = "Which country has won the most World Cup titles?",
		options = { A="Germany", B="Brazil", C="Italy", D="Argentina" }, answer = "B", difficulty = "easy" },
	{ q = "How many teams will compete in the 2026 World Cup?",
		options = { A="32", B="40", C="48", D="64" }, answer = "C", difficulty = "easy" },
	{ q = "Which three countries are co-hosting the 2026 World Cup?",
		options = { A="USA, Mexico, Canada", B="USA, Brazil, Argentina", C="USA, Spain, Portugal", D="Canada, Australia, Japan" }, answer = "A", difficulty = "easy" },
	{ q = "Which country won the 2022 World Cup in Qatar?",
		options = { A="France", B="Brazil", C="Argentina", D="Croatia" }, answer = "C", difficulty = "easy" },
	{ q = "Who scored the infamous 'Hand of God' goal in 1986?",
		options = { A="Ronaldo", B="Diego Maradona", C="Pelé", D="Zinedine Zidane" }, answer = "B", difficulty = "easy" },
	{ q = "What does VAR stand for in football?",
		options = { A="Video Assistant Referee", B="Visual Aid Review", C="Video Action Replay", D="Virtual Assistance Rule" }, answer = "A", difficulty = "easy" },
	{ q = "How many players does each team field during a match?",
		options = { A="9", B="10", C="11", D="12" }, answer = "C", difficulty = "easy" },
	{ q = "In football, what is a 'hat-trick'?",
		options = { A="Scoring 2 goals", B="Scoring 3 goals in one game", C="A penalty save", D="Scoring with your head" }, answer = "B", difficulty = "easy" },
	{ q = "Which country is credited with inventing association football?",
		options = { A="Spain", B="Brazil", C="England", D="Scotland" }, answer = "C", difficulty = "easy" },
	{ q = "Kylian Mbappé plays international football for which country?",
		options = { A="Belgium", B="Ivory Coast", C="France", D="Morocco" }, answer = "C", difficulty = "easy" },
	{ q = "What is a 'bicycle kick' (overhead kick)?",
		options = { A="Kicking with the heel", B="Shooting while jumping and kicking over your own head", C="A backward pass", D="An outside-of-the-foot shot" }, answer = "B", difficulty = "easy" },
	{ q = "What colour card permanently sends a player off the field?",
		options = { A="Yellow", B="Orange", C="Red", D="Blue" }, answer = "C", difficulty = "easy" },
	{ q = "Lionel Messi won the World Cup with which country?",
		options = { A="Brazil", B="Spain", C="Uruguay", D="Argentina" }, answer = "D", difficulty = "easy" },
	{ q = "The 2026 World Cup is the first ever hosted by how many countries?",
		options = { A="1", B="2", C="3", D="4" }, answer = "C", difficulty = "easy" },
	{ q = "In which months is the 2026 World Cup played?",
		options = { A="April–May", B="June–July", C="Nov–Dec", D="Aug–Sept" }, answer = "B", difficulty = "easy" },

	-- ===================== MEDIUM =====================
	{ q = "Who is the all-time top scorer in World Cup history?",
		options = { A="Pelé", B="Ronaldo (Brazil)", C="Miroslav Klose", D="Just Fontaine" }, answer = "C", difficulty = "medium" },
	{ q = "In which year was the very first FIFA World Cup held?",
		options = { A="1924", B="1928", C="1930", D="1934" }, answer = "C", difficulty = "medium" },
	{ q = "Which player won the Golden Boot at the 2018 World Cup?",
		options = { A="Lionel Messi", B="Cristiano Ronaldo", C="Harry Kane", D="Kylian Mbappé" }, answer = "C", difficulty = "medium" },
	{ q = "Who is the youngest player ever to score in a World Cup?",
		options = { A="Wayne Rooney", B="Kylian Mbappé", C="Pelé", D="Cesc Fàbregas" }, answer = "C", difficulty = "medium" },
	{ q = "How far is the penalty spot from the goal line?",
		options = { A="8 yards", B="10 yards", C="12 yards", D="16 yards" }, answer = "C", difficulty = "medium" },
	{ q = "Which player has won the most Ballon d'Or awards?",
		options = { A="Cristiano Ronaldo", B="Lionel Messi", C="Ronaldo (Brazil)", D="Zinedine Zidane" }, answer = "B", difficulty = "medium" },
	{ q = "What is the maximum number of substitutions in a 2026 World Cup match?",
		options = { A="3", B="4", C="5", D="6" }, answer = "C", difficulty = "medium" },
	{ q = "Which country hosted AND won the first World Cup in 1930?",
		options = { A="Argentina", B="Brazil", C="Uruguay", D="Chile" }, answer = "C", difficulty = "medium" },
	{ q = "Which African team reached the semi-finals of the 2022 World Cup?",
		options = { A="Senegal", B="Cameroon", C="Morocco", D="Ghana" }, answer = "C", difficulty = "medium" },
	{ q = "How many groups are there at the 2026 World Cup?",
		options = { A="8", B="10", C="12", D="16" }, answer = "C", difficulty = "medium" },
	{ q = "How many host cities will stage 2026 World Cup matches?",
		options = { A="10", B="12", C="14", D="16" }, answer = "D", difficulty = "medium" },
	{ q = "The 2026 World Cup winners will receive a record prize of about…",
		options = { A="$30 million", B="$42 million", C="$50 million", D="$100 million" }, answer = "C", difficulty = "medium" },
	{ q = "Which country won back-to-back World Cups in 1958 and 1962?",
		options = { A="Italy", B="Brazil", C="Germany", D="Argentina" }, answer = "B", difficulty = "medium" },
	{ q = "In the 2006 final, which player was sent off for a headbutt?",
		options = { A="Zinedine Zidane", B="Marco Materazzi", C="Thierry Henry", D="Ronaldo" }, answer = "A", difficulty = "medium" },
	{ q = "Besides Brazil, which two nations have each won 4 World Cups?",
		options = { A="Germany & Italy", B="Argentina & France", C="Spain & England", D="Uruguay & Netherlands" }, answer = "A", difficulty = "medium" },
	{ q = "Who won the Golden Boot at the 2022 World Cup?",
		options = { A="Lionel Messi", B="Kylian Mbappé", C="Olivier Giroud", D="Julián Álvarez" }, answer = "B", difficulty = "medium" },
	{ q = "Which is the only nation to appear at every World Cup?",
		options = { A="Germany", B="Italy", C="Brazil", D="Argentina" }, answer = "C", difficulty = "medium" },

	-- ===================== HARD =====================
	{ q = "What is the record for most goals by one player in a single World Cup?",
		options = { A="10 — Gerd Müller, 1970", B="13 — Just Fontaine, 1958", C="11 — Sándor Kocsis, 1954", D="8 — Miroslav Klose, 2002" }, answer = "B", difficulty = "hard" },
	{ q = "Which goalkeeper holds the record for most World Cup clean sheets?",
		options = { A="Peter Schmeichel", B="Manuel Neuer", C="Gianluigi Buffon", D="Oliver Kahn" }, answer = "C", difficulty = "hard" },
	{ q = "How many times has Germany (incl. West Germany) reached a World Cup final?",
		options = { A="6", B="7", C="8", D="9" }, answer = "C", difficulty = "hard" },
	{ q = "How many total matches will be played at the 2026 World Cup?",
		options = { A="64", B="80", C="104", D="128" }, answer = "C", difficulty = "hard" },
	{ q = "How many teams advance from the 2026 group stage to the Round of 32?",
		options = { A="16", B="24", C="32", D="48" }, answer = "C", difficulty = "hard" },
	{ q = "Which confederation received the most direct spots for the 2026 World Cup?",
		options = { A="South America", B="Africa", C="Europe", D="Asia" }, answer = "C", difficulty = "hard" },
	{ q = "Which nation is making its World Cup DEBUT in 2026?",
		options = { A="Cabo Verde", B="Egypt", C="Sweden", D="Chile" }, answer = "A", difficulty = "hard" },
	{ q = "Who scored a record FIVE goals in a single World Cup match (1994)?",
		options = { A="Oleg Salenko", B="Gerd Müller", C="Pelé", D="Ronaldo" }, answer = "A", difficulty = "hard" },
	{ q = "What is the fastest goal in World Cup history (2002)?",
		options = { A="~11 seconds", B="~30 seconds", C="~1 minute", D="~2 minutes" }, answer = "A", difficulty = "hard" },
	{ q = "Which player holds the record for most World Cup matches played (26)?",
		options = { A="Lionel Messi", B="Diego Maradona", C="Lothar Matthäus", D="Paolo Maldini" }, answer = "A", difficulty = "hard" },
	{ q = "Which nation returns to the World Cup in 2026 for the first time since 1986?",
		options = { A="Iraq", B="Norway", C="Türkiye", D="Scotland" }, answer = "A", difficulty = "hard" },
	{ q = "Who scored the fastest hat-trick in World Cup history?",
		options = { A="László Kiss (Hungary, 1982)", B="Pelé (Brazil)", C="Geoff Hurst (England)", D="Gerd Müller (Germany)" }, answer = "A", difficulty = "hard" },
} :: { Question }

-- All questions of a given difficulty (the Gauntlet ramps easy -> medium -> hard).
function TriviaBank.byDifficulty(difficulty: Difficulty): { Question }
	local set: { Question } = {}
	for _, q in TriviaBank.Questions do
		if q.difficulty == difficulty then
			table.insert(set, q)
		end
	end
	return set
end

-- Returns 5 questions for today, rotating the start index daily so the set changes.
-- `dayOffset` lets tests override; defaults to today's UTC day number.
function TriviaBank.dailySet(dayOffset: number?): { Question }
	local day = dayOffset or (math.floor(os.time() / 86400))
	local total = #TriviaBank.Questions
	local set: { Question } = {}
	for i = 0, 4 do
		local idx = ((day * 7 + i * 3) % total) + 1 -- pseudo-random but stable per day
		table.insert(set, TriviaBank.Questions[idx])
	end
	return set
end

return TriviaBank
