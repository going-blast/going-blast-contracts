import { exec } from "child_process"

const numBidders = 200
const lot = 0

let lastBidTimestamp = Date.now()

const bid = (userIndex: number, lot: number) => {
	const secondsSinceLastBid = Math.round(Math.abs(Date.now() - lastBidTimestamp) / 1000)
	if (secondsSinceLastBid < 2) {
		console.log(`Skipped user ${userIndex} bid`)
		return
	}
	console.log(`User ${userIndex} bid on lot ${lot}, time since last bid ${secondsSinceLastBid}`)
	lastBidTimestamp = Date.now()

	exec(`yarn script:anvil:bid ${userIndex} ${lot}`, (err, stdout, stderr) => {
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
	const rand = Math.round(Math.random() * 600) + 20
	console.log(`rand ${rand}`)
	return rand
}

const constructBidderIntervals = (n: number) => {
	for (let i = 2; i < n; i++) {
		setInterval(() => {
			bid(i, lot)
		}, getRandomBidInterval() * 1000)
	}
}

const main = async () => {
	constructBidderIntervals(numBidders)
}

main()
