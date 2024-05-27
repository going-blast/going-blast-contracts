import { BigInt } from "@graphprotocol/graph-ts"
import {
	AuctionRune,
	AuctionWindow,
	AuctionEmissions,
	TokenData,
	NftData,
	AuctionRewards,
	AuctionBidData,
	AuctionUser,
	Auction,
	AuctionMessage,
	User,
} from "../../generated/schema"
import {
	Auctioneer,
	Bid as BidEvent,
	SelectedRune as SelectedRuneEvent,
	AuctionCreated as AuctionCreatedEvent,
	AuctionCancelled as AuctionCancelledEvent,
	UserHarvestedLotEmissions as UserHarvestedLotEmissionsEvent,
} from "../../generated/Auctioneer/Auctioneer"
import { AuctioneerAuction, ClaimedLot as ClaimedLotEvent } from "../../generated/AuctioneerAuction/AuctioneerAuction"
import { UpdatedAlias as UpdatedAliasEvent } from "../../generated/AuctioneerUser/AuctioneerUser"

export function handleAuctionCreated(event: AuctionCreatedEvent): void {
	const lot = event.params._lot

	// Contracts
	const auctioneerContract = Auctioneer.bind(event.address)
	const auctioneerAuctionContract = AuctioneerAuction.bind(auctioneerContract.auctioneerAuction())

	// Data
	const auctionExtData = auctioneerAuctionContract.getAuctionExt(lot)
	const auctionData = auctionExtData.getAuction()
	const auctionExt = auctionExtData.getExt()

	// Entities
	const auctionEntity = new Auction(lot.toString())
	const auctionEmissionsEntity = new AuctionEmissions(lot.toString())
	const auctionRewardsEntity = new AuctionRewards(lot.toString())
	const auctionBidDataEntity = new AuctionBidData(lot.toString())

	// Auction
	auctionEntity.lot = lot
	auctionEntity.day = auctionData.day
	auctionEntity.name = auctionData.name
	auctionEntity.isPrivate = auctionData.isPrivate
	auctionEntity.unlockTimestamp = auctionData.unlockTimestamp
	auctionEntity.finalized = auctionData.finalized

	// Auction Emissions
	auctionEmissionsEntity.bp = auctionData.emissions.bp
	auctionEmissionsEntity.biddersEmission = auctionData.emissions.biddersEmission
	auctionEmissionsEntity.treasuryEmission = auctionData.emissions.treasuryEmission
	auctionEntity.emissions = auctionEmissionsEntity.id

	// Auction Rewards
	auctionRewardsEntity.estimatedValue = auctionData.rewards.estimatedValue

	const tokensCount = auctionData.rewards.tokens.length
	const tokenEntityIds = new Array<string>(tokensCount)
	for (let i = 0; i < tokensCount; i++) {
		const token = auctionData.rewards.tokens[i]

		const tokenEntity = new TokenData(lot.toString().concat("_").concat(token.token.toHexString()))
		tokenEntity.token = token.token
		tokenEntity.amount = token.amount
		tokenEntity.save()

		tokenEntityIds[i] = tokenEntity.id
	}
	auctionRewardsEntity.tokens = tokenEntityIds

	const nftsCount = auctionData.rewards.nfts.length
	const nftEntityIds = new Array<string>(nftsCount)
	for (let i = 0; i < nftsCount; i++) {
		const nft = auctionData.rewards.nfts[i]

		const nftEntity = new NftData(lot.toString().concat("_").concat(nft.nft.toHexString()))
		nftEntity.nftId = nft.id
		nftEntity.nft = nft.nft
		nftEntity.save()

		nftEntityIds[i] = nftEntity.id
	}
	auctionRewardsEntity.nfts = nftEntityIds

	auctionEntity.rewards = auctionRewardsEntity.id

	// Auction Bid Data
	auctionBidDataEntity.revenue = auctionData.bidData.revenue
	auctionBidDataEntity.bid = auctionData.bidData.bid
	auctionBidDataEntity.bidTimestamp = auctionData.bidData.bidTimestamp
	auctionBidDataEntity.nextBidBy = auctionData.bidData.nextBidBy
	auctionBidDataEntity.bidUser = auctionData.bidData.bidUser
	auctionBidDataEntity.bidRune = auctionData.bidData.bidRune
	auctionBidDataEntity.bids = auctionData.bidData.bids
	auctionBidDataEntity.bidCost = auctionData.bidData.bidCost
	auctionEntity.bidData = auctionBidDataEntity.id

	// Auction Runes
	const runesCount = auctionData.runes.length
	auctionEntity.hasRunes = runesCount > 0
	const runeEntityIds = new Array<string>(runesCount)
	for (let i = 0; i < runesCount; i++) {
		const rune = auctionData.runes[i]

		const runeEntity = new AuctionRune(lot.toString().concat("_").concat(rune.runeSymbol.toString()))
		runeEntity.runeSymbol = rune.runeSymbol
		runeEntity.bids = rune.bids
		runeEntity.auction = auctionEntity.id
		runeEntity.save()

		runeEntityIds[i] = runeEntity.id
	}
	auctionEntity.runes = runeEntityIds

	// Auction Windows
	const windowsCount = auctionData.windows.length
	const windowEntityIds = new Array<string>(windowsCount)
	for (let i = 0; i < windowsCount; i++) {
		const window = auctionData.windows[i]

		const windowEntity = new AuctionWindow(lot.toString().concat("_").concat(i.toString()))
		windowEntity.windowType = window.windowType === 0 ? "OPEN" : window.windowType === 1 ? "TIMED" : "INFINITE"
		windowEntity.windowOpenTimestamp = window.windowOpenTimestamp
		windowEntity.windowCloseTimestamp = window.windowCloseTimestamp
		windowEntity.timer = window.timer
		windowEntity.save()

		windowEntityIds[i] = windowEntity.id
	}
	auctionEntity.windows = windowEntityIds

	// Ext
	auctionEntity.biddingOpen = auctionExt.isBiddingOpen
	auctionEntity.ended = auctionExt.isEnded
	auctionEntity.cancelled = false
	auctionEntity.activeWindow = auctionExt.activeWindow
	auctionEntity.messagesCount = 1

	// Persist
	auctionEntity.save()
	auctionEmissionsEntity.save()
	auctionRewardsEntity.save()
	auctionBidDataEntity.save()

	// Create info message
	const auctionCreatedMessageEntity = new AuctionMessage(lot.toString().concat("_0"))
	auctionCreatedMessageEntity.type = "INFO"
	auctionCreatedMessageEntity.index = auctionEntity.messagesCount
	auctionCreatedMessageEntity.auction = auctionEntity.id
	auctionCreatedMessageEntity.message = "LOT # ".concat(auctionEntity.name).concat(" CREATED")
	auctionCreatedMessageEntity.tx = event.transaction.hash
	auctionCreatedMessageEntity.timestamp = event.block.timestamp
	auctionCreatedMessageEntity.save()
}

export function handleUpdatedAlias(event: UpdatedAliasEvent): void {
	const user = event.params._user.toHexString()

	let userEntity = User.load(user)

	if (userEntity == null) {
		userEntity = new User(user)
		userEntity.harvestableAuctions = []
		userEntity.totalBidsCount = BigInt.zero()
		userEntity.totalAuctionsParticipated = BigInt.zero()
		userEntity.totalEmissionsHarvested = BigInt.zero()
		userEntity.totalEmissionsBurned = BigInt.zero()
		userEntity.totalAuctionsWon = BigInt.zero()
	}

	userEntity.alias = event.params._alias

	userEntity.save()
}

export function handleSelectedRune(event: SelectedRuneEvent): void {
	const lot = event.params._lot.toString()
	const user = event.params._user.toHexString()

	// ===== CONTRACTS =====

	const auctioneerContract = Auctioneer.bind(event.address)
	const auctioneerAuctionContract = AuctioneerAuction.bind(auctioneerContract.auctioneerAuction())

	const auctionEntity = Auction.load(lot)!
	const userEntity = User.load(user)

	// ===== USER =====

	// Create auction user if not exists
	let auctionUserEntity = AuctionUser.load(lot.concat("_").concat(user))

	if (auctionUserEntity == null) {
		auctionUserEntity = new AuctionUser(lot.concat("_").concat(user))
		auctionUserEntity.user = event.params._user
		auctionUserEntity.auction = lot
		auctionUserEntity.bids = BigInt.zero()
		auctionUserEntity.lastBidTimestamp = BigInt.zero()
		auctionUserEntity.harvested = false
		auctionUserEntity.claimed = false
	}

	// Rune switch pre-calcs
	const prevRuneSymbol = auctionUserEntity.runeSymbol
	const switchedRunesIncursPenalty =
		auctionEntity.hasRunes &&
		prevRuneSymbol !== 0 &&
		prevRuneSymbol !== auctionUserEntity.runeSymbol &&
		auctionUserEntity.bids.gt(BigInt.zero())

	const runeSwitchPenalty = auctioneerAuctionContract.runeSwitchPenalty()
	const userBidsBeforePenalty = auctionUserEntity.bids
	const userBidsAfterPenalty = auctionUserEntity.bids
		.times(BigInt.fromI32(10000).minus(runeSwitchPenalty))
		.div(BigInt.fromI32(10000))

	// Update user
	auctionUserEntity.runeSymbol = event.params._rune
	const selectedRuneEntity = AuctionRune.load(lot.concat("_").concat(event.params._rune.toString()))
	auctionUserEntity.rune = selectedRuneEntity == null ? null : selectedRuneEntity.id

	// Update user bids
	if (switchedRunesIncursPenalty) {
		auctionUserEntity.bids = userBidsAfterPenalty
	}

	auctionUserEntity.save()

	// ===== AUCTION =====

	// Remove bids from auction if user incurred penalty
	if (switchedRunesIncursPenalty) {
		const auctionBidDataEntity = AuctionBidData.load(auctionEntity.bidData)!
		auctionBidDataEntity.bids = auctionBidDataEntity.bids.plus(userBidsAfterPenalty).minus(userBidsBeforePenalty)
		auctionBidDataEntity.save()
	}

	// Increment messages count
	auctionEntity.messagesCount = auctionEntity.messagesCount + 1
	auctionEntity.save()

	// ===== RUNE =====

	if (auctionEntity.hasRunes) {
		const auctionUserRuneEntity = AuctionRune.load(lot.concat("_").concat(auctionUserEntity.runeSymbol.toString()))!

		if (switchedRunesIncursPenalty) {
			// Remove all bids from prev rune
			const auctionUserPrevRuneEntity = AuctionRune.load(
				lot.concat("_").concat(auctionUserEntity.runeSymbol.toString())
			)!
			auctionUserPrevRuneEntity.bids = auctionUserPrevRuneEntity.bids.minus(userBidsBeforePenalty)
			auctionUserPrevRuneEntity.save()

			// Add bids to new rune with penalty taken
			auctionUserRuneEntity.bids = auctionUserRuneEntity.bids.plus(userBidsAfterPenalty)
			auctionUserRuneEntity.save()
		}
	}

	// ===== MESSAGE =====

	const selectRuneMessageEntity = new AuctionMessage(
		lot.toString().concat("_").concat(auctionEntity.messagesCount.toString())
	)
	selectRuneMessageEntity.type = "RUNE"
	selectRuneMessageEntity.index = auctionEntity.messagesCount
	selectRuneMessageEntity.auction = auctionEntity.id
	selectRuneMessageEntity.auctionUser = auctionUserEntity.id
	selectRuneMessageEntity.user = event.params._user
	selectRuneMessageEntity.alias = userEntity == null ? null : userEntity.alias
	selectRuneMessageEntity.prevRuneSymbol = prevRuneSymbol
	selectRuneMessageEntity.runeSymbol = event.params._rune
	// selectRuneMessageEntity.message = event.params._options.message
	selectRuneMessageEntity.tx = event.transaction.hash
	selectRuneMessageEntity.timestamp = event.block.timestamp
	selectRuneMessageEntity.save()
}

export function handleBid(event: BidEvent): void {
	const lot = event.params._lot.toString()
	const user = event.params._user.toHexString()

	// ===== CONTRACTS =====
	const auctioneerContract = Auctioneer.bind(event.address)
	const auctioneerAuctionContract = AuctioneerAuction.bind(auctioneerContract.auctioneerAuction())
	const auctionData = auctioneerAuctionContract.getAuction(event.params._lot)

	const auctionEntity = Auction.load(lot)!
	const auctionEmissionsEntity = AuctionEmissions.load(auctionEntity.emissions)!

	let userEntity = User.load(user)

	// ===== AUCTION USER =====

	// Create user if not exists
	let auctionUserEntity = AuctionUser.load(lot.concat("_").concat(user))

	if (auctionUserEntity == null) {
		auctionUserEntity = new AuctionUser(lot.concat("_").concat(user))
		auctionUserEntity.user = event.params._user
		auctionUserEntity.auction = lot
		auctionUserEntity.bids = BigInt.zero()
		auctionUserEntity.lastBidTimestamp = BigInt.zero()
		auctionUserEntity.harvested = false
		auctionUserEntity.claimed = false
	}

	// Set "isFirstBid" flag
	const isFirstBid = auctionUserEntity.bids.equals(BigInt.zero())

	// Rune switch pre-calcs
	const prevRuneSymbol = auctionUserEntity.runeSymbol
	const switchedRunesIncursPenalty =
		auctionEntity.hasRunes &&
		prevRuneSymbol !== 0 &&
		prevRuneSymbol !== auctionUserEntity.runeSymbol &&
		auctionUserEntity.bids.gt(BigInt.zero())

	let userBidsBeforePenalty = BigInt.zero()
	let userBidsAfterPenalty = BigInt.zero()

	if (switchedRunesIncursPenalty) {
		const runeSwitchPenalty = auctioneerAuctionContract.runeSwitchPenalty()
		userBidsBeforePenalty = auctionUserEntity.bids
		userBidsAfterPenalty = auctionUserEntity.bids
			.times(BigInt.fromI32(10000).minus(runeSwitchPenalty))
			.div(BigInt.fromI32(10000))
	}

	// Update user
	auctionUserEntity.runeSymbol = event.params._options.rune
	const selectedRuneEntity = AuctionRune.load(lot.concat("_").concat(event.params._options.rune.toString()))
	auctionUserEntity.rune = selectedRuneEntity == null ? null : selectedRuneEntity.id
	auctionUserEntity.lastBidTimestamp = event.block.timestamp

	if (switchedRunesIncursPenalty) {
		auctionUserEntity.bids = userBidsAfterPenalty
	}
	auctionUserEntity.bids = auctionUserEntity.bids.plus(event.params._options.multibid)

	auctionUserEntity.save()

	// ===== USER =====

	if (userEntity == null) {
		userEntity = new User(user)
		userEntity.harvestableAuctions = []
		userEntity.totalBidsCount = BigInt.zero()
		userEntity.totalAuctionsParticipated = BigInt.zero()
		userEntity.totalEmissionsHarvested = BigInt.zero()
		userEntity.totalEmissionsBurned = BigInt.zero()
		userEntity.totalAuctionsWon = BigInt.zero()
	}

	userEntity.totalBidsCount = userEntity.totalBidsCount.plus(event.params._options.multibid)
	if (isFirstBid) {
		userEntity.totalAuctionsParticipated = userEntity.totalAuctionsParticipated.plus(BigInt.fromI32(1))
	}
	if (isFirstBid && auctionEmissionsEntity.biddersEmission.gt(BigInt.zero())) {
		userEntity.harvestableAuctions.push(auctionEntity.id)
	}
	userEntity.save()

	// ===== AUCTION =====

	const auctionBidDataEntity = AuctionBidData.load(auctionEntity.bidData)!

	// Update from event
	auctionBidDataEntity.bidUser = event.params._user
	auctionBidDataEntity.bidTimestamp = event.block.timestamp
	auctionBidDataEntity.bidRune = event.params._options.rune

	if (switchedRunesIncursPenalty) {
		// Remove penalized bids
		auctionBidDataEntity.bids = auctionBidDataEntity.bids.plus(userBidsAfterPenalty).minus(userBidsBeforePenalty)
	}
	// Add new bids
	auctionBidDataEntity.bids = auctionBidDataEntity.bids.plus(event.params._options.multibid)

	// Update from contract
	auctionBidDataEntity.bid = auctionData.bidData.bid
	auctionBidDataEntity.revenue = auctionData.bidData.revenue
	auctionBidDataEntity.nextBidBy = auctionData.bidData.nextBidBy
	auctionBidDataEntity.save()

	// ===== RUNE =====

	if (auctionEntity.hasRunes) {
		const auctionUserRuneEntity = AuctionRune.load(lot.concat("_").concat(auctionUserEntity.runeSymbol.toString()))!

		if (switchedRunesIncursPenalty) {
			// Remove all bids from prev rune
			const auctionUserPrevRuneEntity = AuctionRune.load(
				lot.concat("_").concat(auctionUserEntity.runeSymbol.toString())
			)!
			auctionUserPrevRuneEntity.bids = auctionUserPrevRuneEntity.bids.minus(userBidsBeforePenalty)
			auctionUserPrevRuneEntity.save()

			// Add bids to new rune with penalty taken
			auctionUserRuneEntity.bids = auctionUserRuneEntity.bids.plus(userBidsAfterPenalty)
		}

		// Add new bids to users rune
		auctionUserRuneEntity.bids = auctionUserRuneEntity.bids.plus(event.params._options.multibid)
		auctionUserRuneEntity.save()
	}

	// ===== MESSAGE =====

	// Increment message count
	auctionEntity.messagesCount = auctionEntity.messagesCount + 1
	auctionEntity.save()

	// Create bid message entity
	const bidMessageEntity = new AuctionMessage(lot.concat("_").concat(auctionEntity.messagesCount.toString()))
	bidMessageEntity.type = "BID"
	bidMessageEntity.index = auctionEntity.messagesCount
	bidMessageEntity.auction = auctionEntity.id
	bidMessageEntity.auctionUser = auctionUserEntity.id
	bidMessageEntity.user = event.params._user
	bidMessageEntity.alias = event.params._alias
	bidMessageEntity.multibid = event.params._options.multibid
	bidMessageEntity.prevRuneSymbol = prevRuneSymbol
	bidMessageEntity.runeSymbol = event.params._options.rune
	bidMessageEntity.message = event.params._options.message
	bidMessageEntity.bid = event.params._bid
	bidMessageEntity.tx = event.transaction.hash
	bidMessageEntity.timestamp = event.block.timestamp
	bidMessageEntity.save()
}

export function handleAuctionCancelled(event: AuctionCancelledEvent): void {
	const lot = event.params._lot.toString()

	// ===== AUCTION =====

	const auctionEntity = Auction.load(lot)!
	auctionEntity.cancelled = true

	// ===== MESSAGE =====

	// Increment message count
	auctionEntity.messagesCount = auctionEntity.messagesCount + 1
	auctionEntity.save()

	// Create bid message entity
	const cancelledMessageEntity = new AuctionMessage(lot.concat("_").concat(auctionEntity.messagesCount.toString()))
	cancelledMessageEntity.type = "INFO"
	cancelledMessageEntity.index = auctionEntity.messagesCount
	cancelledMessageEntity.auction = auctionEntity.id
	cancelledMessageEntity.message = "CANCELLED"
	cancelledMessageEntity.tx = event.transaction.hash
	cancelledMessageEntity.timestamp = event.block.timestamp
	cancelledMessageEntity.save()
}

export function handleClaimedLot(event: ClaimedLotEvent): void {
	const lot = event.params._lot.toString()
	const user = event.params._user.toString()

	// ===== AUCTION =====

	const auctionEntity = Auction.load(lot)!

	// ===== USER =====

	const userEntity = User.load(user)!
	userEntity.totalAuctionsWon = userEntity.totalAuctionsWon.plus(BigInt.fromI32(1))
	userEntity.save()

	const auctionUserEntity = AuctionUser.load(lot.concat("_").concat(user))!
	auctionUserEntity.claimed = true
	auctionUserEntity.save()

	// ===== MESSAGE =====

	// Increment message count
	auctionEntity.messagesCount = auctionEntity.messagesCount + 1
	auctionEntity.save()

	// Create bid message entity
	const claimedMessageEntity = new AuctionMessage(lot.concat("_").concat(auctionEntity.messagesCount.toString()))
	claimedMessageEntity.type = "CLAIM"
	claimedMessageEntity.index = auctionEntity.messagesCount
	claimedMessageEntity.auction = auctionEntity.id
	claimedMessageEntity.auctionUser = auctionUserEntity.id
	claimedMessageEntity.user = event.params._user
	claimedMessageEntity.alias = userEntity == null ? null : userEntity.alias
	claimedMessageEntity.runeSymbol = auctionUserEntity.runeSymbol
	// TODO: Allow a message to be sent with claiming
	// claimedMessageEntity.message = event.params._options.message
	claimedMessageEntity.tx = event.transaction.hash
	claimedMessageEntity.timestamp = event.block.timestamp
	claimedMessageEntity.save()
}

export function handleUserHarvestedLotEmissions(event: UserHarvestedLotEmissionsEvent): void {
	const lot = event.params._lot.toString()
	const user = event.params._user.toString()

	// ===== USER =====

	const userEntity = User.load(user)!

	const harvestableAuctionsCount = userEntity.harvestableAuctions.length
	const remainingHarvestableAuctionIds = new Array<string>()
	for (let i = 0; i < harvestableAuctionsCount; i++) {
		const harvestableLot = userEntity.harvestableAuctions[i]
		if (harvestableLot !== lot) {
			remainingHarvestableAuctionIds.push(harvestableLot)
		}
	}
	userEntity.harvestableAuctions = remainingHarvestableAuctionIds

	userEntity.totalEmissionsHarvested = userEntity.totalEmissionsHarvested.plus(event.params._userEmissions)
	userEntity.totalEmissionsBurned = userEntity.totalEmissionsBurned.plus(event.params._userEmissions)

	userEntity.save()

	// ===== AUCTION USER =====

	const auctionUserEntity = AuctionUser.load(lot.concat("_").concat(user))!
	auctionUserEntity.harvested = true
	auctionUserEntity.save()
}
