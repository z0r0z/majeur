/**
 * Get DAO Information using MolochViewHelper
 *
 * This script fetches DAO metadata and basic information using the MolochViewHelper contract.
 *
 * Prerequisites:
 *   npm install ethers
 *
 * Usage:
 *   node get-dao-info.js [--rpc RPC_URL] [DAO_ADDRESS]
 *
 * Note: RPC_URL can be provided via:
 *   1. --rpc flag (highest priority)
 *   2. RPC_URL environment variable
 *   3. Default public RPC (lowest priority)
 *
 * Examples:
 *   node get-dao-info.js
 *   node get-dao-info.js 0x2aFF7382EB3e812d8794BFB49A8a51535A646ee2
 *   node get-dao-info.js --rpc https://eth-mainnet.g.alchemy.com/v2/YOUR-KEY
 *   node get-dao-info.js --rpc https://eth-mainnet.g.alchemy.com/v2/YOUR-KEY 0x2aFF7382EB3e812d8794BFB49A8a51535A646ee2
 *   node get-dao-info.js 0x2aFF7382EB3e812d8794BFB49A8a51535A646ee2 --rpc https://eth-mainnet.g.alchemy.com/v2/YOUR-KEY
 */

let ethers;
try {
    ethers = require('ethers');
} catch (e) {
    // Try to find ethers in global npm packages
    try {
        const { execSync } = require('child_process');
        const Module = require('module');

        // Get global npm root
        let globalNodeModules = execSync('npm root -g', { encoding: 'utf8' }).trim();

        // Convert Windows path to WSL path if needed
        if (globalNodeModules.match(/^[A-Z]:/)) {
            const drive = globalNodeModules[0].toLowerCase();
            globalNodeModules = '/mnt/' + drive + globalNodeModules.substring(2).replace(/\\/g, '/');
        }

        // Add to module paths
        Module._nodeModulePaths = Module._nodeModulePaths || [];
        if (!module.paths.includes(globalNodeModules)) {
            module.paths.unshift(globalNodeModules);
        }

        // Also try Node's built-in global paths
        const nodeGlobalPaths = Module.globalPaths || [];
        nodeGlobalPaths.forEach(path => {
            if (!module.paths.includes(path)) {
                module.paths.unshift(path);
            }
        });

        ethers = require('ethers');
    } catch (globalError) {
        console.error('Error: ethers.js not found. Please install it:');
        console.error('  npm install ethers');
        console.error('  or globally: npm install -g ethers');
        process.exit(1);
    }
}

// Constants
const VIEW_HELPER_ADDRESS = "0x00000000006631040967E58e3430e4B77921a2db";
const DEFAULT_DAO_ADDRESS = "0x7a45e6764eCfF2F0eea245ca14a75d6d3d6053b7";
const DEFAULT_RPC_URL = "https://ethereum-sepolia-rpc.publicnode.com";

// ABI for getDAOFullState - simplified to extract what we need
// The full return type is complex, but ethers can decode it automatically
const HELPER_ABI = [
    {
        "inputs": [
            {"internalType": "address", "name": "dao", "type": "address"},
            {"internalType": "uint256", "name": "proposalStart", "type": "uint256"},
            {"internalType": "uint256", "name": "proposalCount", "type": "uint256"},
            {"internalType": "uint256", "name": "messageStart", "type": "uint256"},
            {"internalType": "uint256", "name": "messageCount", "type": "uint256"},
            {"internalType": "address[]", "name": "treasuryTokens", "type": "address[]"}
        ],
        "name": "getDAOFullState",
        "outputs": [
            {
                "components": [
                    {"internalType": "address", "name": "dao", "type": "address"},
                    {
                        "components": [
                            {"internalType": "string", "name": "name", "type": "string"},
                            {"internalType": "string", "name": "symbol", "type": "string"},
                            {"internalType": "string", "name": "contractURI", "type": "string"},
                            {"internalType": "address", "name": "sharesToken", "type": "address"},
                            {"internalType": "address", "name": "lootToken", "type": "address"},
                            {"internalType": "address", "name": "badgesToken", "type": "address"},
                            {"internalType": "address", "name": "renderer", "type": "address"}
                        ],
                        "internalType": "struct DAOMeta",
                        "name": "meta",
                        "type": "tuple"
                    },
                    {
                        "components": [
                            {"internalType": "uint96", "name": "proposalThreshold", "type": "uint96"},
                            {"internalType": "uint96", "name": "minYesVotesAbsolute", "type": "uint96"},
                            {"internalType": "uint96", "name": "quorumAbsolute", "type": "uint96"},
                            {"internalType": "uint64", "name": "proposalTTL", "type": "uint64"},
                            {"internalType": "uint64", "name": "timelockDelay", "type": "uint64"},
                            {"internalType": "uint16", "name": "quorumBps", "type": "uint16"},
                            {"internalType": "bool", "name": "ragequittable", "type": "bool"},
                            {"internalType": "uint256", "name": "autoFutarchyParam", "type": "uint256"},
                            {"internalType": "uint256", "name": "autoFutarchyCap", "type": "uint256"},
                            {"internalType": "address", "name": "rewardToken", "type": "address"}
                        ],
                        "internalType": "struct DAOGovConfig",
                        "name": "gov",
                        "type": "tuple"
                    },
                    {
                        "components": [
                            {"internalType": "uint256", "name": "sharesTotalSupply", "type": "uint256"},
                            {"internalType": "uint256", "name": "lootTotalSupply", "type": "uint256"},
                            {"internalType": "uint256", "name": "sharesHeldByDAO", "type": "uint256"},
                            {"internalType": "uint256", "name": "lootHeldByDAO", "type": "uint256"}
                        ],
                        "internalType": "struct DAOTokenSupplies",
                        "name": "supplies",
                        "type": "tuple"
                    },
                    {
                        "components": [
                            {
                                "components": [
                                    {"internalType": "address", "name": "token", "type": "address"},
                                    {"internalType": "uint256", "name": "balance", "type": "uint256"}
                                ],
                                "internalType": "struct TokenBalance[]",
                                "name": "balances",
                                "type": "tuple[]"
                            }
                        ],
                        "internalType": "struct DAOTreasury",
                        "name": "treasury",
                        "type": "tuple"
                    },
                    {
                        "components": [
                            {"internalType": "address", "name": "account", "type": "address"},
                            {"internalType": "uint256", "name": "shares", "type": "uint256"},
                            {"internalType": "uint256", "name": "loot", "type": "uint256"},
                            {"internalType": "uint16", "name": "seatId", "type": "uint16"},
                            {"internalType": "uint256", "name": "votingPower", "type": "uint256"},
                            {"internalType": "address[]", "name": "delegates", "type": "address[]"},
                            {"internalType": "uint32[]", "name": "delegatesBps", "type": "uint32[]"}
                        ],
                        "internalType": "struct MemberView[]",
                        "name": "members",
                        "type": "tuple[]"
                    },
                    {
                        "components": [
                            {"internalType": "uint256", "name": "id", "type": "uint256"},
                            {"internalType": "address", "name": "proposer", "type": "address"},
                            {"internalType": "uint8", "name": "state", "type": "uint8"},
                            {"internalType": "uint48", "name": "snapshotBlock", "type": "uint48"},
                            {"internalType": "uint64", "name": "createdAt", "type": "uint64"},
                            {"internalType": "uint64", "name": "queuedAt", "type": "uint64"},
                            {"internalType": "uint256", "name": "supplySnapshot", "type": "uint256"},
                            {"internalType": "uint96", "name": "forVotes", "type": "uint96"},
                            {"internalType": "uint96", "name": "againstVotes", "type": "uint96"},
                            {"internalType": "uint96", "name": "abstainVotes", "type": "uint96"},
                            {
                                "components": [
                                    {"internalType": "bool", "name": "enabled", "type": "bool"},
                                    {"internalType": "address", "name": "rewardToken", "type": "address"},
                                    {"internalType": "uint256", "name": "pool", "type": "uint256"},
                                    {"internalType": "bool", "name": "resolved", "type": "bool"},
                                    {"internalType": "uint8", "name": "winner", "type": "uint8"},
                                    {"internalType": "uint256", "name": "finalWinningSupply", "type": "uint256"},
                                    {"internalType": "uint256", "name": "payoutPerUnit", "type": "uint256"}
                                ],
                                "internalType": "struct FutarchyView",
                                "name": "futarchy",
                                "type": "tuple"
                            },
                            {
                                "components": [
                                    {"internalType": "address", "name": "voter", "type": "address"},
                                    {"internalType": "uint8", "name": "support", "type": "uint8"},
                                    {"internalType": "uint256", "name": "weight", "type": "uint256"}
                                ],
                                "internalType": "struct VoterView[]",
                                "name": "voters",
                                "type": "tuple[]"
                            }
                        ],
                        "internalType": "struct ProposalView[]",
                        "name": "proposals",
                        "type": "tuple[]"
                    },
                    {
                        "components": [
                            {"internalType": "uint256", "name": "index", "type": "uint256"},
                            {"internalType": "string", "name": "text", "type": "string"}
                        ],
                        "internalType": "struct MessageView[]",
                        "name": "messages",
                        "type": "tuple[]"
                    }
                ],
                "internalType": "struct DAOLens",
                "name": "out",
                "type": "tuple"
            }
        ],
        "stateMutability": "view",
        "type": "function"
    }
];

/**
 * Fetch DAO information
 */
async function getDAOInfo(daoAddress, rpcUrl) {
    const provider = new ethers.JsonRpcProvider(rpcUrl);
    const helper = new ethers.Contract(VIEW_HELPER_ADDRESS, HELPER_ABI, provider);

    console.log('Fetching DAO information...\n');
    console.log('DAO Address:', daoAddress);
    console.log('View Helper:', VIEW_HELPER_ADDRESS);
    console.log('');

    try {
        // Fetch state: 0 proposals, 0 messages, and check ETH (address(0)) balance
        const state = await helper.getDAOFullState(
            daoAddress,
            0,  // proposalStart
            0,  // proposalCount
            0,  // messageStart
            0,  // messageCount
            ["0x0000000000000000000000000000000000000000"] // treasuryTokens (ETH)
        );

        console.log('=== DAO Metadata ===');
        console.log('Name:', state.meta.name);
        console.log('Symbol:', state.meta.symbol);
        console.log('DAO Emblem URL (Contract URI):', state.meta.contractURI);
        console.log('Shares Token:', state.meta.sharesToken);
        console.log('Loot Token:', state.meta.lootToken);
        console.log('Badges Token:', state.meta.badgesToken);
        console.log('Renderer:', state.meta.renderer);
        console.log('');

        console.log('=== Token Supplies ===');
        console.log('Shares Total Supply:', state.supplies.sharesTotalSupply.toString());
        console.log('Loot Total Supply:', state.supplies.lootTotalSupply.toString());
        console.log('Shares Held by DAO:', state.supplies.sharesHeldByDAO.toString());
        console.log('Loot Held by DAO:', state.supplies.lootHeldByDAO.toString());
        console.log('');

        console.log('=== Treasury ===');
        if (state.treasury.balances && state.treasury.balances.length > 0) {
            state.treasury.balances.forEach((bal, i) => {
                const token = bal.token === "0x0000000000000000000000000000000000000000" ? "ETH" : bal.token;
                console.log(`  ${token}: ${ethers.formatEther(bal.balance)}`);
            });
        } else {
            console.log('  No treasury balances checked');
        }
        console.log('');

        console.log('=== Governance Config ===');
        console.log('Proposal Threshold:', state.gov.proposalThreshold.toString());
        console.log('Min Yes Votes (Absolute):', state.gov.minYesVotesAbsolute.toString());
        console.log('Quorum (Absolute):', state.gov.quorumAbsolute.toString());
        console.log('Proposal TTL:', state.gov.proposalTTL.toString(), 'seconds');
        console.log('Timelock Delay:', state.gov.timelockDelay.toString(), 'seconds');
        console.log('Quorum BPS:', state.gov.quorumBps.toString());
        console.log('Ragequittable:', state.gov.ragequittable);
        console.log('Auto Futarchy Param:', state.gov.autoFutarchyParam.toString());
        console.log('Auto Futarchy Cap:', state.gov.autoFutarchyCap.toString());
        console.log('Reward Token:', state.gov.rewardToken);
        console.log('');

        console.log('=== Members ===');
        console.log('Member Count:', state.members.length);
        if (state.members.length > 0) {
            console.log('Top Members:');
            state.members.slice(0, 5).forEach((member, i) => {
                console.log(`  ${i + 1}. ${member.account}`);
                console.log(`     Shares: ${member.shares.toString()}, Loot: ${member.loot.toString()}, Voting Power: ${member.votingPower.toString()}`);
                if (member.seatId > 0) {
                    console.log(`     Badge Seat: ${member.seatId}`);
                }
            });
            if (state.members.length > 5) {
                console.log(`  ... and ${state.members.length - 5} more`);
            }
        }
        console.log('');

        console.log('=== Proposals ===');
        console.log('Proposal Count:', state.proposals.length);
        console.log('(Note: Set proposalCount > 0 to fetch proposals)');
        console.log('');

        console.log('=== Messages ===');
        console.log('Message Count:', state.messages.length);
        console.log('(Note: Set messageCount > 0 to fetch messages)');

    } catch (error) {
        console.error('Error fetching DAO info:', error.message);
        if (error.data) {
            console.error('Error data:', error.data);
        }
        throw error;
    }
}

/**
 * Parse --rpc flag from arguments
 * Returns { rpcUrl, positionalArgs }
 */
function parseArgs(args) {
    let rpcUrl = null;
    const positionalArgs = [];

    for (let i = 0; i < args.length; i++) {
        if (args[i] === '--rpc' && i + 1 < args.length) {
            rpcUrl = args[i + 1];
            i++; // Skip the next argument (the URL)
        } else if (!args[i].startsWith('--')) {
            positionalArgs.push(args[i]);
        }
    }

    return { rpcUrl, positionalArgs };
}

// CLI interface
async function main() {
    const args = process.argv.slice(2);

    // Parse --rpc flag
    let { rpcUrl, positionalArgs } = parseArgs(args);

    // Check environment variable if --rpc not provided
    if (!rpcUrl) {
        rpcUrl = process.env.RPC_URL;
    }

    // Backward compatibility: if first positional arg looks like a URL, treat it as RPC
    if (!rpcUrl && positionalArgs.length > 0 &&
        (positionalArgs[0].startsWith('http://') || positionalArgs[0].startsWith('https://'))) {
        rpcUrl = positionalArgs.shift();
    }

    // Show usage if no args provided and no RPC configured
    if (!rpcUrl && positionalArgs.length < 1) {
        console.log('Usage: node get-dao-info.js [--rpc RPC_URL] [DAO_ADDRESS]');
        console.log('\nOptions:');
        console.log('  --rpc RPC_URL   Specify RPC endpoint URL');
        console.log('\nNote: RPC_URL can also be provided via RPC_URL environment variable');
        console.log('      If not provided, defaults to:', DEFAULT_RPC_URL);
        console.log('\nExamples:');
        console.log('  node get-dao-info.js');
        console.log('  node get-dao-info.js 0x2aFF7382EB3e812d8794BFB49A8a51535A646ee2');
        console.log('  node get-dao-info.js --rpc https://eth-mainnet.g.alchemy.com/v2/YOUR-KEY');
        console.log('  node get-dao-info.js --rpc https://eth-mainnet.g.alchemy.com/v2/YOUR-KEY 0x2aFF7382EB3e812d8794BFB49A8a51535A646ee2');
        console.log('  node get-dao-info.js 0x2aFF7382EB3e812d8794BFB49A8a51535A646ee2 --rpc https://eth-mainnet.g.alchemy.com/v2/YOUR-KEY');
    }

    // Use default RPC URL if still not set
    if (!rpcUrl) {
        rpcUrl = DEFAULT_RPC_URL;
        console.log(`\nUsing default RPC URL: ${DEFAULT_RPC_URL}\n`);
    }

    const daoAddress = positionalArgs[0] || DEFAULT_DAO_ADDRESS;

    try {
        await getDAOInfo(daoAddress, rpcUrl);
    } catch (error) {
        console.error('Error:', error.message);
        process.exit(1);
    }
}

// Run if executed directly
if (require.main === module) {
    main();
}

module.exports = { getDAOInfo };
