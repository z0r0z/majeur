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
const DEFAULT_PROPOSAL_START = 0;
const DEFAULT_PROPOSAL_COUNT = 0;
const DEFAULT_MESSAGE_START = 0;
const DEFAULT_MESSAGE_COUNT = 0;

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
 * Format 18-decimal number as e18 notation (e.g., 1000e18 instead of 1000000000000000000000)
 */
function formatE18(value) {
    if (!value || value === '0' || value === 0) {
        return '0';
    }

    // Handle BigInt, string, or BigNumber
    let bigValue;
    if (typeof value === 'bigint') {
        bigValue = BigInt(value);
    } else if (typeof value === 'string') {
        bigValue = BigInt(value);
    } else {
        // Assume it's a BigNumber or number - convert to string first
        bigValue = BigInt(value.toString());
    }

    const divisor = BigInt('1000000000000000000'); // 1e18

    // Check if it's a clean multiple of 1e18
    if (bigValue % divisor === BigInt(0)) {
        const wholePart = bigValue / divisor;
        return `${wholePart.toString()}e18`;
    }

    // If not a clean multiple, show with decimals using ethers
    // Convert BigInt to string for formatUnits
    return ethers.formatUnits(bigValue.toString(), 18);
}

/**
 * Convert IPFS URL to gateway URL for fetching
 */
function toGatewayUrl(url) {
    if (!url || typeof url !== 'string') return url;

    // Already a gateway URL
    if (url.startsWith('http://') || url.startsWith('https://')) {
        return url;
    }

    // IPFS protocol
    if (url.startsWith('ipfs://')) {
        const hash = url.replace('ipfs://', '');
        return `https://ipfs.io/ipfs/${hash}`;
    }

    // IPNS protocol
    if (url.startsWith('ipns://')) {
        const name = url.replace('ipns://', '');
        return `https://ipfs.io/ipns/${name}`;
    }

    return url;
}

/**
 * Fetch and display contractURI content
 */
async function displayContractURIContent(contractURI) {
    console.log('=== Contract URI ===');

    if (!contractURI || contractURI.trim() === '') {
        console.log('URI: (empty - using default renderer)');
        console.log('Default: Wyoming DUNA covenant card (generated on-chain)');
        console.log('');
        return;
    }

    console.log('URI:', contractURI);
    console.log('');

    try {
        // Handle data URIs
        if (contractURI.startsWith('data:')) {
            if (contractURI.startsWith('data:application/json')) {
                console.log('📄 Type: JSON Metadata (data URI)');
                console.log('');

                let jsonStr;
                // Check specifically for data:application/json;base64, prefix (not just any ;base64,)
                if (contractURI.startsWith('data:application/json;base64,')) {
                    const base64 = contractURI.substring('data:application/json;base64,'.length);
                    jsonStr = Buffer.from(base64, 'base64').toString('utf8');
                } else if (contractURI.startsWith('data:application/json;utf8,')) {
                    jsonStr = contractURI.substring('data:application/json;utf8,'.length);
                } else if (contractURI.startsWith('data:application/json,')) {
                    jsonStr = contractURI.substring('data:application/json,'.length);
                } else {
                    // Fallback: try to find the first comma after data:
                    const commaIndex = contractURI.indexOf(',');
                    if (commaIndex !== -1) {
                        jsonStr = contractURI.substring(commaIndex + 1);
                    } else {
                        jsonStr = contractURI;
                    }
                }

                try {
                    const metadata = JSON.parse(jsonStr);
                    console.log('Content:');
                    console.log(JSON.stringify(metadata, null, 2));
                    console.log('');
                } catch (e) {
                    console.log('⚠️  Could not parse JSON:', e.message);
                    console.log(`   First 200 chars of extracted content: ${jsonStr.substring(0, 200)}...`);
                    console.log(`   Content length: ${jsonStr.length} chars`);
                }
            } else if (contractURI.startsWith('data:image/')) {
                console.log('📷 Type: Image (data URI)');
                console.log('Size: ~' + Math.round(contractURI.length / 1024) + ' KB (base64 encoded)');
            } else {
                console.log('📄 Type: Data URI (unknown format)');
            }
        } else {
            // Fetch from URL
            const fetchUrl = toGatewayUrl(contractURI);
            console.log(`Fetching from: ${fetchUrl}`);
            console.log('');

            // Use built-in fetch (Node 18+) or require node-fetch for older versions
            let fetchFunc;
            try {
                // Try built-in fetch first (Node 18+)
                if (typeof globalThis.fetch !== 'undefined') {
                    fetchFunc = globalThis.fetch;
                } else if (typeof fetch !== 'undefined') {
                    fetchFunc = fetch;
                } else {
                    throw new Error('No built-in fetch');
                }
            } catch (e) {
                // Fallback to node-fetch for older Node versions
                try {
                    const nodeFetch = require('node-fetch');
                    fetchFunc = nodeFetch.default || nodeFetch;
                } catch (e2) {
                    console.log('⚠️  Cannot fetch URL: fetch is not available.');
                    console.log('   Install node-fetch for Node < 18: npm install node-fetch');
                    console.log('   Or upgrade to Node 18+ for built-in fetch support');
                    console.log('');
                    return;
                }
            }

            // Create AbortController for timeout (Node 18+ has this built-in)
            let controller;
            let timeoutId;
            try {
                controller = new AbortController();
                timeoutId = setTimeout(() => controller.abort(), 10000);
            } catch (e) {
                // AbortController not available, skip timeout
                controller = null;
            }

            const fetchOptions = {
                headers: {
                    'Accept': 'application/json, image/*'
                }
            };

            if (controller) {
                fetchOptions.signal = controller.signal;
            }

            let response;
            try {
                response = await fetchFunc(fetchUrl, fetchOptions);
            } catch (error) {
                if (timeoutId) {
                    clearTimeout(timeoutId);
                }
                if (error.name === 'AbortError' || error.message.includes('aborted')) {
                    console.log('⚠️  Request timeout (10 seconds). URL may be slow or unreachable.');
                } else {
                    console.log(`⚠️  Failed to fetch: ${error.message}`);
                }
                console.log('');
                return;
            }

            if (timeoutId) {
                clearTimeout(timeoutId);
            }

            if (!response.ok) {
                console.log(`⚠️  Failed to fetch: HTTP ${response.status} ${response.statusText}`);
                console.log('');
                return;
            }

            const contentType = response.headers.get('content-type') || '';

            if (contentType.includes('application/json')) {
                console.log('📄 Type: JSON Metadata');
                console.log('');
                const metadata = await response.json();
                console.log('Content:');
                console.log(JSON.stringify(metadata, null, 2));
                console.log('');
            } else if (contentType.startsWith('image/')) {
                console.log('📷 Type: Image');
                console.log(`Content-Type: ${contentType}`);
                const contentLength = response.headers.get('content-length');
                if (contentLength) {
                    console.log(`Size: ${Math.round(parseInt(contentLength) / 1024)} KB`);
                }
            } else if (contentType.includes('text/')) {
                const text = await response.text();
                console.log('📄 Type: Text');
                console.log(`Content-Type: ${contentType}`);
                console.log(`Content (first 500 chars):`);
                console.log(text.substring(0, 500) + (text.length > 500 ? '...' : ''));
            } else {
                console.log(`📄 Type: Unknown (${contentType})`);
                const text = await response.text();
                console.log(`Content (first 200 chars):`);
                console.log(text.substring(0, 200) + (text.length > 200 ? '...' : ''));
            }
        }
    } catch (error) {
        console.log(`⚠️  Error fetching contractURI content: ${error.message}`);
        if (error.code === 'ECONNREFUSED' || error.code === 'ETIMEDOUT') {
            console.log('   (Connection timeout or refused - URL may be invalid or unreachable)');
        } else if (error.name === 'AbortError') {
            console.log('   (Request timeout - URL took too long to respond)');
        }
        console.log('');
    }
}

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
        // Fetch state: proposals and messages
        const proposalStart = DEFAULT_PROPOSAL_START;
        const proposalCount = DEFAULT_PROPOSAL_COUNT;
        const messageStart = DEFAULT_MESSAGE_START;
        const messageCount = DEFAULT_MESSAGE_COUNT;

        console.log(`Fetching proposals: indices ${proposalStart} to ${proposalStart + proposalCount - 1}`);
        console.log(`Fetching messages: indices ${messageStart} to ${messageStart + messageCount - 1}`);
        console.log('');

        const state = await helper.getDAOFullState(
            daoAddress,
            proposalStart,
            proposalCount,
            messageStart,
            messageCount,
            ["0x0000000000000000000000000000000000000000"] // treasuryTokens (ETH)
        );

        console.log('=== DAO Metadata ===');
        console.log('Name:', state.meta.name);
        console.log('Symbol:', state.meta.symbol);
        console.log('Shares Token:', state.meta.sharesToken);
        console.log('Loot Token:', state.meta.lootToken);
        console.log('Badges Token:', state.meta.badgesToken);
        console.log('Renderer:', state.meta.renderer);
        console.log('');

        // Fetch and display contractURI content
        await displayContractURIContent(state.meta.contractURI);

        console.log('=== Token Supplies ===');
        console.log('Shares Total Supply:', formatE18(state.supplies.sharesTotalSupply));
        console.log('Loot Total Supply:', formatE18(state.supplies.lootTotalSupply));
        console.log('Shares Held by DAO:', formatE18(state.supplies.sharesHeldByDAO));
        console.log('Loot Held by DAO:', formatE18(state.supplies.lootHeldByDAO));
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
        console.log('Proposal Threshold:', formatE18(state.gov.proposalThreshold));
        console.log('Min Yes Votes (Absolute):', formatE18(state.gov.minYesVotesAbsolute));
        console.log('Quorum (Absolute):', formatE18(state.gov.quorumAbsolute));
        console.log('Proposal TTL:', state.gov.proposalTTL.toString(), 'seconds');
        console.log('Timelock Delay:', state.gov.timelockDelay.toString(), 'seconds');
        console.log('Quorum BPS:', state.gov.quorumBps.toString());
        console.log('Ragequittable:', state.gov.ragequittable);
        console.log('Auto Futarchy Param:', formatE18(state.gov.autoFutarchyParam));
        console.log('Auto Futarchy Cap:', formatE18(state.gov.autoFutarchyCap));
        console.log('Reward Token:', state.gov.rewardToken);
        console.log('');

        console.log('=== Members ===');
        console.log('Member Count:', state.members.length);
        if (state.members.length > 0) {
            console.log('All Members:');
            state.members.forEach((member, i) => {
                console.log(`  ${i + 1}. ${member.account}`);
                console.log(`     Shares: ${formatE18(member.shares)}, Loot: ${formatE18(member.loot)}, Voting Power: ${formatE18(member.votingPower)}`);
                if (member.seatId > 0) {
                    console.log(`     Badge Seat: ${member.seatId}`);
                }
            });
        }
        console.log('');

        console.log('=== Proposals ===');
        console.log('Proposal Count:', state.proposals.length);
        if (state.proposals.length > 0) {
            const stateNames = ['Unopened', 'Active', 'Queued', 'Succeeded', 'Defeated', 'Expired', 'Executed'];
            state.proposals.forEach((proposal, i) => {
                console.log(`\n  Proposal ${i + 1}:`);
                console.log(`    ID: ${proposal.id.toString()}`);
                console.log(`    Proposer: ${proposal.proposer}`);
                console.log(`    State: ${stateNames[proposal.state] || proposal.state} (${proposal.state})`);
                console.log(`    Created At: ${new Date(Number(proposal.createdAt) * 1000).toISOString()}`);
                if (proposal.queuedAt > 0) {
                    console.log(`    Queued At: ${new Date(Number(proposal.queuedAt) * 1000).toISOString()}`);
                }
                console.log(`    Snapshot Block: ${proposal.snapshotBlock.toString()}`);
                console.log(`    Votes - For: ${formatE18(proposal.forVotes)}, Against: ${formatE18(proposal.againstVotes)}, Abstain: ${formatE18(proposal.abstainVotes)}`);
                if (proposal.futarchy.enabled) {
                    console.log(`    Futarchy: Enabled (Pool: ${formatE18(proposal.futarchy.pool)}, Resolved: ${proposal.futarchy.resolved})`);
                }
                if (proposal.voters && proposal.voters.length > 0) {
                    console.log(`    Voters (${proposal.voters.length}):`);
                    proposal.voters.forEach((voter, j) => {
                        const supportNames = ['Against', 'For', 'Abstain'];
                        console.log(`      ${j + 1}. ${voter.voter} - ${supportNames[voter.support] || voter.support} (Weight: ${formatE18(voter.weight)})`);
                    });
                }
            });
        } else {
            console.log(`(No proposals fetched. Set DEFAULT_PROPOSAL_COUNT > 0 to fetch proposals)`);
        }
        console.log('');

        console.log('=== Messages ===');
        console.log('Message Count:', state.messages.length);
        if (state.messages.length > 0) {
            state.messages.forEach((message, i) => {
                console.log(`\n  Message ${i + 1}:`);
                console.log(`    Index: ${message.index.toString()}`);
                console.log(`    Text: ${message.text}`);
            });
        } else {
            console.log(`(No messages fetched. Set DEFAULT_MESSAGE_COUNT > 0 to fetch messages)`);
        }

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
