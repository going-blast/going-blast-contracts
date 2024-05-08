import { exec } from "child_process"
import { rand, randCatchPhrase } from "@ngneat/falso"

const numBidders = 70

let lastBidTimestamp = Date.now()

type BidderData = {
	index: number
	lot: number
	rune: number
	interval: number
}

const bidderData: Record<string, BidderData> = {}
const bidderAggregate: Record<number, Record<number, number>> = {}
const lotMinBidInterval: Record<number, number> = {}

const bid = (userIndex: number) => {
	const bidder = bidderData[userIndex]
	if (bidder == null) return
	const { lot, rune } = bidder

	const secondsSinceLastBid = Math.round(Math.abs(Date.now() - lastBidTimestamp) / 1000)
	if (secondsSinceLastBid < 2) {
		console.log(`Skipped user ${userIndex} bid`)
		return
	}

	const message = randCatchPhrase()
	console.log(
		`User ${userIndex} bid(lot <${lot}>, rune <${rune}>, message <${message}>). time since last bid ${secondsSinceLastBid}`
	)
	lastBidTimestamp = Date.now()

	exec(`yarn script:anvil:bid ${userIndex} ${lot} ${rune} "${message}"`, (err, stdout, stderr) => {
		if (err) {
			console.log("error", err)
			// node couldn't execute the command
			return
		}

		// the *entire* stdout and stderr (buffered)
		console.log(`stdout: ${stdout}`)
		console.log(`stderr: ${stderr}`)
	})
}

const getRandomBidInterval = () => {
	const rand = Math.round(Math.random() * 300) + 20
	console.log(`rand ${rand}`)
	return rand
}

const constructBidderIntervals = () => {
	Object.values(bidderData).forEach((bidder) => {
		setInterval(() => {
			bid(bidder.index)
		}, bidder.interval)
	})
}

const createBidders = (n: number) => {
	for (let i = 2; i < n; i++) {
		const lot = rand([0, 1])
		const rune = lot === 0 ? 0 : rand([1, 2, 3])
		const interval = getRandomBidInterval() * 1000
		bidderData[i] = {
			index: i,
			lot,
			rune,
			interval,
		}

		// Bidder count aggregate
		if (bidderAggregate[lot] == null) {
			bidderAggregate[lot] = {}
		}
		if (bidderAggregate[lot][rune] == null) {
			bidderAggregate[lot][rune] = 0
		}
		bidderAggregate[lot][rune] += 1

		// Lot interval count
		if (lotMinBidInterval[lot] == null) {
			lotMinBidInterval[lot] = Infinity
		}
		if (interval < lotMinBidInterval[lot]) {
			lotMinBidInterval[lot] = interval
		}
	}
}

const main = async () => {
	createBidders(numBidders)
	constructBidderIntervals()
	console.log(JSON.stringify(bidderAggregate, null, 2))
	console.log(JSON.stringify(lotMinBidInterval, null, 2))
}

main()
