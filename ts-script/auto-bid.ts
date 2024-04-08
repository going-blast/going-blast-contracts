import { exec } from "child_process"

const bid = (userIndex: number, lot: number) => {
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

const main = async () => {
	bid(2, 0)
	setInterval(() => {
		console.log("hello there")
		bid(2, 0)
	}, 60 * 1000)
}

main()
