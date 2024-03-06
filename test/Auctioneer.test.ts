import { expect } from "chai"
import { deployments, ethers, getNamedAccounts } from "hardhat"
import {
	getTimestamp,
	increaseTimestampAndMine,
	mineBlock,
	mineBlockWithTimestamp,
	topOfNextHourTimestamp,
} from "../utils/base"
import { ZeroAddress } from "ethers"

describe.only("Auctioneer", () => {
	const setupFixture = deployments.createFixture(async () => {
		await deployments.fixture()
		const signers = await getNamedAccounts()

		const deployer = await ethers.getSigner(signers.deployer)
		const treasury = await ethers.getSigner(signers.owner)
		const user1 = await ethers.getSigner(signers.user1)
		const user2 = await ethers.getSigner(signers.user2)
		const user3 = await ethers.getSigner(signers.user3)

		const USD = await ethers.deployContract("BasicERC20", ["Fake Stable", "USD", deployer.address], deployer)
		const WETH = await ethers.deployContract("BasicERC20", ["Fake WETH", "WETH", deployer], deployer)

		await USD.mint(deployer.address, ethers.parseUnits("1000"))
		await USD.mint(treasury.address, ethers.parseUnits("1000"))
		await USD.mint(user1.address, ethers.parseUnits("1000"))
		await USD.mint(user2.address, ethers.parseUnits("1000"))
		await USD.mint(user3.address, ethers.parseUnits("1000"))

		await WETH.mint(deployer.address, ethers.parseUnits("2"))
		await WETH.mint(treasury.address, ethers.parseUnits("2"))
		await WETH.mint(user1.address, ethers.parseUnits("2"))
		await WETH.mint(user2.address, ethers.parseUnits("2"))
		await WETH.mint(user3.address, ethers.parseUnits("2"))

		const auctioneer = await ethers.deployContract(
			"Auctioneer",
			[USD.target, ethers.parseUnits("0.01"), 120, ethers.parseUnits("1")],
			deployer
		)
		const vault = await ethers.deployContract("AuctioneerVault", [], deployer)

		await USD.connect(deployer).approve(auctioneer.target, ethers.parseUnits("1000"))
		await USD.connect(treasury).approve(auctioneer.target, ethers.parseUnits("1000"))
		await USD.connect(user1).approve(auctioneer.target, ethers.parseUnits("1000"))
		await USD.connect(user2).approve(auctioneer.target, ethers.parseUnits("1000"))
		await USD.connect(user3).approve(auctioneer.target, ethers.parseUnits("1000"))

		await WETH.connect(deployer).approve(auctioneer.target, ethers.parseUnits("1000"))
		await WETH.connect(treasury).approve(auctioneer.target, ethers.parseUnits("1000"))
		await WETH.connect(user1).approve(auctioneer.target, ethers.parseUnits("1000"))
		await WETH.connect(user2).approve(auctioneer.target, ethers.parseUnits("1000"))
		await WETH.connect(user3).approve(auctioneer.target, ethers.parseUnits("1000"))

		return {
			auctioneer,
			vault,
			USD,
			WETH,
			deployer,
			treasury,
			user1,
			user2,
			user3,
		}
	})

	const setupFixtureWithAuctionAndCuts = deployments.createFixture(async () => {
		const data = await setupFixture()

		// Set cuts
		await data.auctioneer.setTreasury(data.treasury.address)
		await data.auctioneer.setTreasurySplit(5000)

		// Create auction
		const unlockTimestamp = await topOfNextHourTimestamp()
		await data.auctioneer.create(data.WETH.target, ethers.parseUnits("1"), "Gavel", unlockTimestamp)

		return { ...data, auctionId: 0 }
	})

	describe("setTreasury", async () => {
		it("reverts if zero address", async () => {
			const { auctioneer, vault, deployer, treasury } = await setupFixture()
			await expect(auctioneer.setTreasury(treasury.address)).to.be.revertedWithCustomError(
				auctioneer,
				"ZeroAddress"
			)
		})
		it("succeeds", async () => {
			const { auctioneer, vault, deployer, treasury } = await setupFixture()
			await expect(auctioneer.setTreasury(treasury.address))
				.to.emit(auctioneer, "UpdatedTreasury")
				.withArgs(treasury.address)
		})
	})
	describe("setReceivers", async () => {
		it("reverts if fees too high", async () => {
			const { auctioneer, vault, deployer, treasury } = await setupFixture()
			await expect(auctioneer.setTreasury(treasury.address)).to.be.revertedWithCustomError(
				auctioneer,
				"ZeroAddress"
			)
		})
		it("reverts if cut set without address", async () => {
			const { auctioneer, deployer, treasury, vault } = await setupFixture()

			await expect(
				auctioneer.setReceivers(treasury.address, 500, ethers.ZeroAddress, 500)
			).to.be.revertedWithCustomError(auctioneer, "ZeroAddress")

			await expect(
				auctioneer.setReceivers(ethers.ZeroAddress, 500, vault.target, 500)
			).to.be.revertedWithCustomError(auctioneer, "ZeroAddress")
		})
		it("succeeds", async () => {
			const { auctioneer, deployer, treasury, vault } = await setupFixture()
			await expect(auctioneer.setReceivers(treasury.address, 500, vault.target, 1000)).to.not.be.reverted
			expect(await auctioneer.TREASURY()).to.eq(treasury.address)
			expect(await auctioneer.TREASURY_CUT()).to.eq(500)
			expect(await auctioneer.VAULT()).to.eq(vault.target)
			expect(await auctioneer.VAULT_CUT()).to.eq(1000)
		})
	})
	it("create", async () => {
		const { auctioneer, deployer, WETH } = await setupFixture()

		const auctionId = 0
		const unlockTimestamp = await topOfNextHourTimestamp()

		const deployerWethInit = await WETH.balanceOf(deployer.address)
		const auctioneerWethInit = await WETH.balanceOf(auctioneer.target)

		await expect(auctioneer.create(WETH.target, ethers.parseUnits("1"), "Gavel", unlockTimestamp))
			.to.emit(auctioneer, "AuctionCreated")
			.withArgs(auctionId, deployer.address)

		const deployerWethFinal = await WETH.balanceOf(deployer.address)
		const auctioneerWethFinal = await WETH.balanceOf(auctioneer.target)

		expect(deployerWethInit - deployerWethFinal).to.eq(ethers.parseUnits("1"))
		expect(auctioneerWethFinal - auctioneerWethInit).to.eq(ethers.parseUnits("1"))

		const auction = await auctioneer.getAuction(auctionId)

		expect(auction.id).to.eq(auctionId)
		expect(auction.owner).to.eq(deployer.address)
		expect(auction.unlockTimestamp).to.eq(unlockTimestamp)
		expect(auction.sum).to.eq(0)
		expect(auction.bid).to.eq(ethers.parseUnits("1"))
		expect(auction.bidUser).to.eq(deployer.address)
		expect(auction.name).to.eq("Gavel")
		expect(auction.finalized).to.eq(false)
		expect(auction.amount).to.eq(ethers.parseUnits("1"))
	})
	it("cancel", async () => {
		const { auctioneer, deployer, user1, WETH } = await setupFixture()

		// Create auction
		let auctionId = 0
		let unlockTimestamp = await topOfNextHourTimestamp()
		await auctioneer.create(WETH.target, ethers.parseUnits("1"), "Gavel", unlockTimestamp)

		// . Revert invalid auction id
		await expect(auctioneer.connect(deployer).cancel(auctionId + 1)).to.be.revertedWithCustomError(
			auctioneer,
			"InvalidAuctionId"
		)

		// . Revert user is not auction owner
		await expect(auctioneer.connect(user1).cancel(auctionId)).to.be.revertedWithCustomError(
			auctioneer,
			"PermissionDenied"
		)

		// . Succeed if not unlocked, user recovers tokens
		const wethInit = await WETH.balanceOf(deployer.address)

		await expect(auctioneer.connect(deployer).cancel(auctionId))
			.to.emit(auctioneer, "AuctionCancelled")
			.withArgs(auctionId, deployer.address)

		const wethFinal = await WETH.balanceOf(deployer.address)
		expect(wethFinal - wethInit).to.eq(ethers.parseEther("1"))

		const { finalized } = await auctioneer.getAuction(auctionId)
		expect(finalized).to.eq(true)

		// Create new auction
		auctionId = 1
		unlockTimestamp = await topOfNextHourTimestamp()
		await auctioneer.create(WETH.target, ethers.parseUnits("0.5"), "Gavel 2", unlockTimestamp)

		// . Revert auction already begun
		await mineBlockWithTimestamp(unlockTimestamp)
		await auctioneer.connect(user1).bid(auctionId)
		await expect(auctioneer.connect(deployer).cancel(auctionId)).to.be.revertedWithCustomError(
			auctioneer,
			"NotCancellable"
		)
	})
	describe("bidWindow(uint256 _aid)", async () => {
		it("revert invalid id", async () => {
			const { auctioneer, deployer, user1, WETH, USD, auctionId } = await setupFixtureWithAuctionAndCuts()
			await expect(auctioneer.biddingWindow(auctionId + 1)).to.be.revertedWithCustomError(
				auctioneer,
				"InvalidAuctionId"
			)
		})
		it("correct all the way through window", async () => {
			const { auctioneer, deployer, user1, WETH, USD, auctionId } = await setupFixtureWithAuctionAndCuts()

			const { unlockTimestamp: unlockTimestampRaw } = await auctioneer.getAuction(auctionId)
			const unlockTimestamp = parseInt(unlockTimestampRaw.toString())
			const startingTimestamp = unlockTimestamp - 10
			const closingTimestamp = unlockTimestamp + 120
			await mineBlockWithTimestamp(startingTimestamp)

			for (let i = 0; i < 200; i++) {
				await mineBlock()
				const trueTimestamp = await getTimestamp()
				const biddingWindow = await auctioneer.biddingWindow(auctionId)

				if (trueTimestamp < unlockTimestamp) {
					expect(biddingWindow.open).to.eq(false)
					expect(biddingWindow.timeRemaining).to.eq(0)
				}
				if (trueTimestamp >= unlockTimestamp && trueTimestamp <= closingTimestamp) {
					expect(biddingWindow.open).to.eq(true)
					expect(biddingWindow.timeRemaining).to.eq(closingTimestamp - trueTimestamp)
				}
				if (trueTimestamp > closingTimestamp) {
					expect(biddingWindow.open).to.eq(false)
					expect(biddingWindow.timeRemaining).to.eq(0)
				}
			}
		})
	})
	describe("bid(uint256 _aid)", async () => {
		it("revert invalid id", async () => {
			const { auctioneer, deployer, user1, WETH, USD, auctionId } = await setupFixtureWithAuctionAndCuts()
			await expect(auctioneer.connect(user1).bid(auctionId + 1)).to.be.revertedWithCustomError(
				auctioneer,
				"InvalidAuctionId"
			)
		})
		it("revert not open", async () => {
			const { auctioneer, deployer, user1, WETH, USD, auctionId } = await setupFixtureWithAuctionAndCuts()
			await expect(auctioneer.connect(user1).bid(auctionId)).to.be.revertedWithCustomError(
				auctioneer,
				"AuctionNotOpen"
			)
		})
		it("revert after bid window closes", async () => {
			const { auctioneer, deployer, user1, WETH, USD, auctionId } = await setupFixtureWithAuctionAndCuts()

			const { unlockTimestamp } = await auctioneer.getAuction(auctionId)
			await mineBlockWithTimestamp(parseInt(unlockTimestamp.toString()))

			const [biddingOpen, bidTimeRemaining] = await auctioneer.biddingWindow(auctionId)
			await increaseTimestampAndMine(parseInt(bidTimeRemaining.toString()))

			await await expect(auctioneer.connect(user1).bid(auctionId)).to.be.revertedWithCustomError(
				auctioneer,
				"AuctionClosed"
			)
		})
		it("succeeds", async () => {
			const { auctioneer, deployer, user1, WETH, USD, auctionId } = await setupFixtureWithAuctionAndCuts()

			const userUsdInit = await USD.balanceOf(user1.address)

			const { unlockTimestamp } = await auctioneer.getAuction(auctionId)
			await mineBlockWithTimestamp(parseInt(unlockTimestamp.toString()))
			await expect(auctioneer.connect(user1).bid(auctionId))
				.to.emit(auctioneer, "Bid")
				.withArgs(auctionId, user1.address, ethers.parseUnits("1.01"))

			const userUsdFinal = await USD.balanceOf(user1.address)
			expect(userUsdInit - userUsdFinal).to.eq(ethers.parseUnits("1.01"))

			const auction = await auctioneer.getAuction(auctionId)
			expect(auction.bidUser).to.eq(user1.address)
			expect(auction.bid).to.eq(ethers.parseUnits("1.01"))
			expect(auction.sum).to.eq(ethers.parseUnits("1.01"))
			expect(auction.bidTimestamp).to.be.closeTo(unlockTimestamp, 2)
		})
	})
	describe("claimWinnings(uint256 _aid) / finalizeOnBehalf(uint256 _aid)", async () => {
		it("revert invalid id", async () => {
			const { auctioneer, deployer, user1, WETH, USD, auctionId } = await setupFixtureWithAuctionAndCuts()
			await expect(auctioneer.connect(user1).bid(auctionId + 1)).to.be.revertedWithCustomError(
				auctioneer,
				"InvalidAuctionId"
			)
		})
		it("reverts if not ended", async () => {
			const { auctioneer, vault, deployer, treasury, user1, user2, WETH, USD, auctionId } =
				await setupFixtureWithAuctionAndCuts()

			const { unlockTimestamp } = await auctioneer.getAuction(auctionId)
			await mineBlockWithTimestamp(parseInt(unlockTimestamp.toString()))

			await auctioneer.connect(user1).bid(auctionId)
			await auctioneer.connect(user2).bid(auctionId)

			await expect(auctioneer.connect(user2).claimWinnings(auctionId)).to.be.revertedWithCustomError(
				auctioneer,
				"AuctionNotOver"
			)
		})
		it("reverts if already finalized", async () => {
			const { auctioneer, vault, deployer, treasury, user1, user2, WETH, USD, auctionId } =
				await setupFixtureWithAuctionAndCuts()

			const { unlockTimestamp } = await auctioneer.getAuction(auctionId)
			await mineBlockWithTimestamp(parseInt(unlockTimestamp.toString()))

			await auctioneer.connect(user1).bid(auctionId)
			await auctioneer.connect(user2).bid(auctionId)

			const auction = await auctioneer.getAuction(auctionId)
			await mineBlockWithTimestamp(parseInt(auction.bidTimestamp.toString()) + 120)

			await expect(auctioneer.connect(user2).claimWinnings(auctionId))
				.to.emit(auctioneer, "AuctionFinalized")
				.withArgs(auctionId)

			await expect(auctioneer.connect(user2).claimWinnings(auctionId)).to.be.revertedWithCustomError(
				auctioneer,
				"AlreadyFinalized"
			)
		})
		it("claimWinnings reverts if not winning user", async () => {
			const { auctioneer, vault, deployer, treasury, user1, user2, WETH, USD, auctionId } =
				await setupFixtureWithAuctionAndCuts()

			const { unlockTimestamp } = await auctioneer.getAuction(auctionId)
			await mineBlockWithTimestamp(parseInt(unlockTimestamp.toString()))

			await auctioneer.connect(user1).bid(auctionId)
			await auctioneer.connect(user2).bid(auctionId)

			const auction = await auctioneer.getAuction(auctionId)
			await mineBlockWithTimestamp(parseInt(auction.bidTimestamp.toString()) + 120)

			await expect(auctioneer.connect(user1).claimWinnings(auctionId)).to.be.revertedWithCustomError(
				auctioneer,
				"NotWinner"
			)
		})
		it("claimWinnings succeeds", async () => {
			const { auctioneer, vault, deployer, treasury, user1, user2, WETH, USD, auctionId } =
				await setupFixtureWithAuctionAndCuts()

			const { unlockTimestamp } = await auctioneer.getAuction(auctionId)
			await mineBlockWithTimestamp(parseInt(unlockTimestamp.toString()))

			for (let i = 0; i < 20; i++) {
				await auctioneer.connect(user1).bid(auctionId)
				await auctioneer.connect(user2).bid(auctionId)
			}

			let auction = await auctioneer.getAuction(auctionId)
			await mineBlockWithTimestamp(parseInt(auction.bidTimestamp.toString()) + 120)

			const user2WethInit = await WETH.balanceOf(user2)
			const auctionUSD = auction.sum
			expect(await USD.balanceOf(auctioneer.target)).to.eq(auctionUSD)

			const ownerCut = (auctionUSD * 5000n) / 10000n
			const treasuryCut = (auctionUSD * 3000n) / 10000n
			const vaultCut = (auctionUSD * 2000n) / 10000n
			const ownerUsdInit = await USD.balanceOf(deployer.address)
			const treasuryUsdInit = await USD.balanceOf(treasury.address)
			const vaultUsdInit = await USD.balanceOf(vault.target)

			await expect(auctioneer.connect(user2).claimWinnings(auctionId))
				.to.emit(auctioneer, "AuctionFinalized")
				.withArgs(auctionId)

			const user2WethFinal = await WETH.balanceOf(user2)
			const ownerUsdFinal = await USD.balanceOf(deployer.address)
			const treasuryUsdFinal = await USD.balanceOf(treasury.address)
			const vaultUsdFinal = await USD.balanceOf(vault.target)

			await expect(user2WethFinal - user2WethInit).to.eq(ethers.parseUnits("1"))
			expect(await USD.balanceOf(auctioneer.target)).to.eq(0)

			expect(ownerUsdFinal - ownerUsdInit).to.eq(ownerCut)
			expect(treasuryUsdFinal - treasuryUsdInit).to.eq(treasuryCut)
			expect(vaultUsdFinal - vaultUsdInit).to.eq(vaultCut)

			// Auction data
			auction = await auctioneer.getAuction(auctionId)
			expect(auction.finalized).to.eq(true)
		})
		it("finalizeOnBehalf succeeds", async () => {
			const { auctioneer, vault, deployer, treasury, user1, user2, WETH, USD, auctionId } =
				await setupFixtureWithAuctionAndCuts()

			const { unlockTimestamp } = await auctioneer.getAuction(auctionId)
			await mineBlockWithTimestamp(parseInt(unlockTimestamp.toString()))

			for (let i = 0; i < 20; i++) {
				await auctioneer.connect(user1).bid(auctionId)
				await auctioneer.connect(user2).bid(auctionId)
			}

			const auction = await auctioneer.getAuction(auctionId)
			await mineBlockWithTimestamp(parseInt(auction.bidTimestamp.toString()) + 120)

			await expect(auctioneer.connect(user1).finalizeOnBehalf(auctionId))
				.to.emit(auctioneer, "AuctionFinalized")
				.withArgs(auctionId)
		})
	})
})
