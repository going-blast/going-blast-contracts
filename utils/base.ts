import { Block } from "ethers"
import { ethers } from "hardhat"

// FUNCTIONS
export const getBlock = async (): Promise<Block> => {
	return (await ethers.provider.getBlock("latest"))!
}
export const getBlockNumber = async (): Promise<number> => {
	return (await getBlock()).number
}
export const getTimestamp = async (): Promise<number> => {
	return (await getBlock()).timestamp
}
export const setTimestamp = async (timestamp: number) => {
	const currentTimestamp = await getTimestamp()
	await ethers.provider.send("evm_setNextBlockTimestamp", [Math.max(timestamp, currentTimestamp + 2)])
}
export const increaseTimestampAndMine = async (increment: number) => {
	await ethers.provider.send("evm_increaseTime", [increment])
	await mineBlock()
}
export const mineBlock = async () => {
	await ethers.provider.send("evm_mine")
}
export const mineBlockWithTimestamp = async (timestamp: number) => {
	await setTimestamp(timestamp)
	await mineBlock()
}
export const mineBlocks = async (blockCount: number) => {
	for (let i = 0; i < blockCount; i++) {
		await mineBlock()
	}
}

export const topOfNextHourTimestamp = async () => {
	const timestamp = await getTimestamp()
	return timestamp + (3600 - (timestamp % 3600))
}
export const nextDay2PMTimestamp = async () => {
	const timestamp = await getTimestamp()
	const dayInS = 24 * 60 * 60
	const hourInS = 60 * 60
	return Math.floor(timestamp / dayInS) * dayInS + 14 * hourInS
}

enum BidWindowType {
	OPEN = 0,
	TIMED = 1,
	INFINITE = 2,
}

type BidWindowParams = {
	windowType: BidWindowType
	duration: number
	timer: number
}

type AuctionParams = {
	isPrivate: boolean
	emissionBP: number
	tokens: string[]
	amounts: string[]
	name: string
	windows: BidWindowParams[]
	unlockTimestamp: number
}

export const getDailyAuctionParams = async (): AuctionParams[] => {
	const unlockTimestamp = await nextDay2PMTimestamp()
}
