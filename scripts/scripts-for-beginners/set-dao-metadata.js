/**
 * Generate Proposal Data for Setting DAO Metadata
 *
 * This script generates the inputs needed to create a governance proposal
 * to update DAO metadata (name, symbol, contractURI).
 *
 * Note: The URI parameter is the contractURI (contract-level metadata URI), which can be:
 *   - An IPFS/IPNS URL (e.g., "ipfs://Qm..." or "https://ipfs.io/ipfs/...")
 *   - An HTTP/HTTPS URL pointing to JSON metadata
 *   - A data URI with JSON metadata (e.g., "data:application/json;utf8,{...}")
 *   - An empty string to use the default renderer-generated DUNA covenant card
 *
 * IMPORTANT: The smart contract does NOT parse or validate the JSON. It only stores
 * and returns the URI string. The JSON is parsed by external tools (OpenSea, wallets, dapps).
 *
 * If providing JSON metadata, use the OpenSea/ERC standard format:
 *   {
 *     "name": "...",           // Optional: redundant with on-chain name (used in Majeur.html modal)
 *     "symbol": "...",         // Optional: redundant with on-chain symbol (parsed but not displayed)
 *     "description": "...",    // USED: displayed in both Majeur.html and DAICO.html dapps
 *     "image": "...",          // USED: logo/emblem URL displayed in both dapps (IPFS/HTTP/data URI)
 *     "external_link": "...",  // Optional: parsed but not currently used by dapps
 *     "banner_image": "...",   // Optional: parsed but not currently used by dapps
 *     "featured_image": "...", // Optional: OpenSea standard (not used by dapps)
 *     "collaborators": [...]   // Optional: OpenSea standard (not used by dapps)
 *     "attributes": [...]      // Optional: NFT-style attributes (used in Majeur.html modal)
 *   }
 *
 * ACTUALLY USED BY THE DAPPS:
 *   - "description": Shown in DAO emblem area and purchase pages
 *   - "image": Displayed as DAO logo/emblem
 *   - "name": Used in modal titles (Majeur.html only)
 *   - "attributes": Displayed in NFT modal (Majeur.html only)
 *
 * The contract doesn't parse the JSON - it's purely for external consumers.
 * You can also provide a direct image URL instead of JSON (less common).
 *
 * Prerequisites:
 *   npm install ethers
 *   npm install clipboardy (optional, for clipboard support; falls back to OS commands)
 *
 * Usage:
 *   node set-dao-metadata.js [--rpc RPC_URL]
 *
 * Note: RPC_URL can be provided via:
 *   1. --rpc flag (highest priority)
 *   2. RPC_URL environment variable
 *   3. Default public RPC (lowest priority)
 *
 *   The script runs in interactive mode and will prompt for:
 *   - DAO Address
 *   - DAO Name
 *   - DAO Symbol
 *   - Contract URI: Option to:
 *       a) Build contractURI JSON automatically (include description/image that dapps will display)
 *       b) Provide a custom URI (IPFS/HTTP URL or data URI)
 *       c) Skip (use default renderer-generated DUNA covenant card)
 *   - Proposal Description (optional, for the governance proposal text itself)
 *
 *   NOTE: The "Proposal Description" is different from the DAO description!
 *   - Proposal Description: Text shown with the governance proposal
 *   - DAO Description: Goes into contractURI JSON and is displayed in dapps (if you choose option a)
 *
 * Examples:
 *   # Interactive mode (prompts for all values)
 *   node set-dao-metadata.js
 *   node set-dao-metadata.js --rpc https://eth-mainnet.g.alchemy.com/v2/YOUR-KEY
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

// Clipboard functionality
let clipboardy;
try {
    clipboardy = require('clipboardy');
} catch (e) {
    // Try global installation (same pattern as ethers)
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

        clipboardy = require('clipboardy');
    } catch (globalError) {
        // Fallback to native OS commands
        clipboardy = null;
    }
}

/**
 * Detect if running in WSL2
 */
function isWSL() {
    try {
        const fs = require('fs');
        const os = require('os');
        // Check /proc/version for WSL indicators
        if (fs.existsSync('/proc/version')) {
            const version = fs.readFileSync('/proc/version', 'utf8');
            if (version.includes('Microsoft') || version.includes('WSL')) {
                return true;
            }
        }
        // Check if uname contains Microsoft
        try {
            const { execSync } = require('child_process');
            const uname = execSync('uname -a', { encoding: 'utf8' });
            if (uname.includes('Microsoft') || uname.includes('WSL')) {
                return true;
            }
        } catch (e) {
            // Ignore
        }
        return false;
    } catch (e) {
        return false;
    }
}

/**
 * Copy text to clipboard using clipboardy or native OS commands
 */
function copyToClipboard(text) {
    const { execSync, spawnSync } = require('child_process');
    const os = require('os');
    const fs = require('fs');

    // Try clipboardy first
    if (clipboardy) {
        try {
            clipboardy.writeSync(text);
            return true;
        } catch (error) {
            // Fall through to native commands
        }
    }

    // Check if we're in WSL
    const inWSL = isWSL();
    const platform = os.platform();

    // Fallback to native OS commands
    try {
        // For WSL or Windows, try PowerShell first (works well in WSL2)
        if (inWSL || platform === 'win32' || platform.includes('win')) {
            // Method 1: Direct PowerShell with base64 encoding (most reliable, no file I/O)
            try {
                const base64 = Buffer.from(text, 'utf8').toString('base64');
                const proc = spawnSync('powershell.exe', [
                    '-NoProfile',
                    '-NonInteractive',
                    '-Command',
                    `[System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String('${base64}')) | Set-Clipboard`
                ], {
                    stdio: 'ignore',
                    timeout: 5000
                });
                if (proc.status === 0 || proc.status === null) return true;
            } catch (e) {
                // Try next method
            }

            // Method 2: Use PowerShell with temp file (fallback if base64 has issues)
            try {
                const tmpPath = '/tmp/clipboard_' + Date.now() + '.txt';
                fs.writeFileSync(tmpPath, text, 'utf8');

                // Convert to Windows path if in WSL
                let winTmpPath = tmpPath;
                if (inWSL && tmpPath.startsWith('/tmp/')) {
                    try {
                        const winTmp = execSync('wslpath -w /tmp', { encoding: 'utf8', stdio: 'pipe' }).trim();
                        winTmpPath = winTmp + '\\' + tmpPath.split('/').pop();
                    } catch (e) {
                        // Try using the Linux path directly
                        winTmpPath = tmpPath;
                    }
                }

                const proc = spawnSync('powershell.exe', [
                    '-NoProfile',
                    '-NonInteractive',
                    '-Command',
                    `Get-Content -Path '${winTmpPath.replace(/\\/g, '/')}' -Raw | Set-Clipboard`
                ], {
                    stdio: 'ignore',
                    timeout: 5000
                });
                // Clean up temp file
                try { fs.unlinkSync(tmpPath); } catch (e) {}
                if (proc.status === 0 || proc.status === null) return true;
            } catch (e) {
                // Try next method
            }

            // Method 2: Use clip.exe with cmd.exe and echo
            try {
                // Write to temp file first (more reliable in WSL)
                const tmpPath = '/tmp/clipboard_' + Date.now() + '.txt';
                fs.writeFileSync(tmpPath, text, 'utf8');

                // Use cmd.exe to copy file contents to clipboard
                const clipPath = '/mnt/c/Windows/System32/clip.exe';
                if (fs.existsSync(clipPath)) {
                    const proc = spawnSync('cmd.exe', [
                        '/c',
                        'type',
                        tmpPath.replace(/^\/tmp\//, 'C:\\temp\\').replace(/\//g, '\\'),
                        '|',
                        clipPath
                    ], {
                        shell: true,
                        stdio: 'ignore'
                    });
                    // Clean up temp file
                    try { fs.unlinkSync(tmpPath); } catch (e) {}
                    if (proc.status === 0) return true;
                }
            } catch (e) {
                // Try direct clip.exe with stdin
            }

            // Method 3: Direct clip.exe with stdin (may work in some WSL setups)
            try {
                const clipPaths = [
                    '/mnt/c/Windows/System32/clip.exe',
                    'clip.exe'
                ];

                for (const clipPath of clipPaths) {
                    try {
                        const proc = spawnSync(clipPath, [], {
                            input: text,
                            encoding: 'utf8',
                            stdio: ['pipe', 'ignore', 'ignore']
                        });
                        if (proc.status === 0 || proc.status === null) return true;
                    } catch (e) {
                        continue;
                    }
                }
            } catch (e) {
                // Ignore
            }
        }

        // For Linux (non-WSL), try xclip/xsel
        if (platform === 'linux' && !inWSL) {
            // Try xclip first, then xsel
            try {
                execSync('which xclip', { stdio: 'ignore' });
                const proc = spawnSync('xclip', ['-selection', 'clipboard'], {
                    input: text,
                    encoding: 'utf8'
                });
                if (proc.status === 0) return true;
            } catch (e) {
                try {
                    execSync('which xsel', { stdio: 'ignore' });
                    const proc = spawnSync('xsel', ['--clipboard', '--input'], {
                        input: text,
                        encoding: 'utf8'
                    });
                    if (proc.status === 0) return true;
                } catch (e2) {
                    // Ignore
                }
            }
        }

        // macOS
        if (platform === 'darwin') {
            const proc = spawnSync('pbcopy', [], {
                input: text,
                encoding: 'utf8'
            });
            if (proc.status === 0) return true;
        }
    } catch (error) {
        // Silently fail
        return false;
    }

    return false;
}

// Constants
const DEFAULT_RPC_URL = "https://ethereum-sepolia-rpc.publicnode.com";

// ABI for setMetadata function
const MOLOCH_ABI = [
    'function setMetadata(string calldata n, string calldata s, string calldata uri)'
];

/**
 * Generate proposal data for setting DAO metadata
 */
async function generateProposalData(daoAddress, name, symbol, uri, description, rpcUrl) {
    // Create interface for encoding
    const molochInterface = new ethers.Interface(MOLOCH_ABI);

    // Encode the setMetadata function call
    const data = molochInterface.encodeFunctionData('setMetadata', [name, symbol, uri]);

    // Proposal parameters
    const targetAddress = daoAddress;
    const value = "0"; // No ETH needed
    const op = 0; // 0 = call, 1 = delegatecall (use 0 for setMetadata)

    // Generate a nonce (you can also provide a custom one)
    // For proposals, nonce is typically a random bytes32 or a specific identifier
    const nonce = ethers.hexlify(ethers.randomBytes(32));

    // Calculate proposal ID (optional, for reference)
    let proposalId = null;
    if (rpcUrl) {
        try {
            const provider = new ethers.JsonRpcProvider(rpcUrl);
            const molochContract = new ethers.Contract(daoAddress, [
                'function proposalId(uint8 op, address to, uint256 value, bytes calldata data, bytes32 nonce) view returns (uint256)'
            ], provider);
            proposalId = await molochContract.proposalId(op, targetAddress, value, data, nonce);
        } catch (error) {
            console.warn('Warning: Could not calculate proposal ID:', error.message);
        }
    }

    return {
        targetAddress,
        value,
        data,
        op,
        nonce,
        proposalId,
        description: description || `Update DAO metadata: name="${name}", symbol="${symbol}", contractURI="${uri || "(default renderer)"}"`
    };
}

/**
 * Display proposal data in a user-friendly format
 */
function displayProposalData(proposalData) {
    // Copy DATA (HEX) to clipboard
    const copied = copyToClipboard(proposalData.data);

    console.log('\n' + '='.repeat(60));
    console.log('PROPOSAL DATA FOR SETTING DAO METADATA');
    console.log('='.repeat(60));
    console.log('\n📋 Use these values in your governance UI:\n');
    console.log('These are the encoded parameters needed to create a governance proposal.');
    console.log('The proposal ID is calculated deterministically - see details below.\n');

    console.log('TARGET ADDRESS:');
    console.log(`  ${proposalData.targetAddress}\n`);

    console.log('VALUE (ETH):');
    console.log(`  ${proposalData.value}\n`);

    console.log('DATA (HEX):');
    console.log(`  ${proposalData.data}`);
    if (copied) {
        console.log('  ✅ Copied to clipboard!\n');
    } else {
        console.log('  ⚠️  Could not copy to clipboard automatically\n');
    }

    console.log('NONCE (bytes32 hex):');
    console.log(`  ${proposalData.nonce}`);
    console.log('  ⚠️  IMPORTANT: Copy this nonce to the dapp\'s "Nonce" field to match the calculated proposal ID!\n');

    console.log('DESCRIPTION:');
    console.log(`  ${proposalData.description}\n`);

    console.log('─'.repeat(60));
    console.log('PROPOSAL PARAMETERS (Technical Details):\n');

    // Operation Type explanation
    console.log('Operation Type:');
    console.log(`  Value: ${proposalData.op} ${proposalData.op === 0 ? '(CALL)' : '(DELEGATECALL)'}`);
    console.log('');
    console.log('  CALL (0) - Currently selected:');
    console.log('    • Meaning: Execute function call on target address');
    console.log('    • Context: Code runs in target contract\'s storage');
    console.log('    • msg.sender: DAO contract address');
    console.log('    • Storage: Target contract\'s storage is modified');
    console.log('    • Use case: Normal function calls (like setMetadata, transfer tokens, etc.)');
    console.log('    • ✅ Correct for setting DAO metadata\n');
    console.log('  DELEGATECALL (1) - Alternative option:');
    console.log('    • Meaning: Execute code in DAO\'s storage context');
    console.log('    • Context: Code runs as if it was part of the DAO contract');
    console.log('    • msg.sender: Original caller (not DAO address)');
    console.log('    • Storage: DAO contract\'s storage is modified');
    console.log('    • Use case: Contract upgrades, module installation, low-level operations');
    console.log('    • ⚠️  Not typically used for setMetadata (would try to modify DAO storage)');
    console.log('    • ⚠️  Dangerous if target contract\'s storage layout differs from DAO\n');

    // Nonce explanation
    console.log('Nonce (bytes32):');
    console.log(`  Value: ${proposalData.nonce}`);
    console.log('  Purpose: Makes this proposal unique');
    console.log('  Why needed:');
    console.log('    • Allows multiple proposals with same parameters');
    console.log('    • Prevents proposal ID collisions');
    console.log('    • Enables proposal versioning/tracking');
    console.log('  How it works:');
    console.log('    • Proposal ID = hash(DAO, op, target, value, data, nonce, config)');
    console.log('    • Different nonce = different proposal ID');
    console.log('    • Same nonce = same proposal ID (prevents duplicates)\n');
    console.log('  💡 Tip: You can use a descriptive nonce like:');
    console.log('    • Random (current): Generated for uniqueness');
    console.log('    • Custom: keccak256("update-metadata-v2") for versioning');
    console.log('    • Sequential: keccak256("proposal-123") for numbering\n');

    // Proposal ID explanation
    if (proposalData.proposalId) {
        console.log('Proposal ID (calculated):');
        console.log(`  Value: ${proposalData.proposalId.toString()}`);
        console.log('  How calculated:');
        console.log('    keccak256(daoAddress, op, target, value, keccak256(data), nonce, config)');
        console.log('  Why this is helpful:');
        console.log('    ✅ Know the ID before creating the proposal');
        console.log('    ✅ Check if proposal already exists');
        console.log('    ✅ Share proposal ID with others in advance');
        console.log('    ✅ Build UI/links before proposal is created');
        console.log('    ✅ Verify proposal parameters match your intent');
        console.log('  🔍 You can verify this ID by calling:');
        console.log(`    moloch.proposalId(${proposalData.op}, "${proposalData.targetAddress}", ${proposalData.value}, <data>, "${proposalData.nonce}")\n`);
    } else {
        console.log('Proposal ID:');
        console.log('  ⚠️  Could not calculate (RPC not available or failed)');
        console.log('  You can calculate it manually using:');
        console.log('    moloch.proposalId(op, target, value, data, nonce)\n');
    }

    console.log('─'.repeat(60));
    console.log('📝 SUMMARY:\n');
    console.log('• Operation Type: 0 (CALL) - Standard function execution');
    console.log('• Nonce: Randomly generated for uniqueness');
    if (proposalData.proposalId) {
        console.log(`• Proposal ID: ${proposalData.proposalId.toString()} (calculated in advance)`);
    }
    console.log('\n✅ All values are ready to use in your governance UI!\n');
}

/**
 * Interactive mode: prompt for all values
 */
async function interactiveMode(rpcUrl) {
    const readline = require('readline');
    const rl = readline.createInterface({
        input: process.stdin,
        output: process.stdout
    });

    const question = (prompt) => new Promise((resolve) => {
        rl.question(prompt, resolve);
    });

    try {
        console.log('\n📝 Interactive Mode: Enter DAO Metadata\n');

        // Prompt for DAO address
        const daoAddress = await question('DAO Address: ');
        if (!daoAddress.trim()) {
            throw new Error('DAO Address is required');
        }
        const finalDaoAddress = daoAddress.trim();

        const name = await question('DAO Name: ');
        if (!name.trim()) {
            throw new Error('Name is required');
        }

        const symbol = await question('DAO Symbol: ');
        if (!symbol.trim()) {
            throw new Error('Symbol is required');
        }

        // Ask about contractURI strategy
        console.log('\n' + '─'.repeat(60));
        console.log('CONTRACT URI STRATEGY');
        console.log('─'.repeat(60));
        console.log('\nHow do you want to set the contractURI?');
        console.log('\n  Option 1: Build JSON metadata here → Store as data URI on-chain');
        console.log('    - You provide description/image');
        console.log('    - Script creates JSON and embeds it in a data URI');
        console.log('    - Everything stored on-chain (can be large for big descriptions)');
        console.log('\n  Option 2: Provide existing URI (IPFS/IPNS/HTTP)');
        console.log('    - You provide a URI that points to your JSON metadata');
        console.log('    - Examples:');
        console.log('      • ipfs://QmYourHashHere (direct IPFS CID)');
        console.log('      • ipfs://ipns/k51qzi5... (IPNS name)');
        console.log('      • https://ipfs.io/ipfs/Qm... (IPFS gateway URL)');
        console.log('      • https://example.com/dao-metadata.json (HTTP URL)');
        console.log('      • data:application/json;utf8,{...} (data URI with JSON)');
        console.log('\n  Option 3: Empty (use default)');
        console.log('    - Leave empty to use the default Wyoming DUNA covenant card');
        console.log('    - Generated on-chain by the renderer contract');
        console.log('');

        const strategy = await question('Choose option (1/2/3, default: 3): ').then(a => a.trim().toLowerCase() || '3');
        let finalUri = '';

        if (strategy === '1') {
            console.log('\n📝 Building JSON metadata...\n');
            // Build contractURI JSON similar to dapps
            const daoDescription = await question('DAO Description (optional, for contractURI JSON): ');
            const imageUrl = await question('Image URL (optional, for contractURI JSON - IPFS/HTTP/data URI): ');
            const useBase64 = await question('Use base64 encoding in data URI? (y/n, default: n) - More compact but less readable: ');

            const hasDescription = daoDescription.trim().length > 0;
            const hasImage = imageUrl.trim().length > 0;

            if (hasDescription || hasImage) {
                const metadata = {
                    name: name.trim(),
                    symbol: symbol.trim()
                };

                if (hasDescription) {
                    metadata.description = daoDescription.trim();
                }

                if (hasImage) {
                    metadata.image = imageUrl.trim();
                }

                const json = JSON.stringify(metadata, null, 2); // Pretty-printed for display
                const jsonCompact = JSON.stringify(metadata); // Compact for data URI

                // Display the full JSON for IPFS upload
                console.log('\n' + '='.repeat(60));
                console.log('📄 JSON METADATA (for reference / IPFS upload later)');
                console.log('='.repeat(60));
                console.log('\nThis is the JSON that will be embedded in the data URI:\n');
                console.log(json);
                console.log('\n');

                // Copy JSON to clipboard if possible
                const jsonCopied = copyToClipboard(json);
                if (jsonCopied) {
                    console.log('✅ JSON copied to clipboard!\n');
                }

                console.log('💡 Tip: If you want to use IPFS/IPNS instead of data URI:');
                console.log('   - Upload this JSON to IPFS (via IPFS Desktop or pinning service)');
                console.log('   - Get the IPFS CID (Qm... or bafy...)');
                console.log('   - Optionally create/update IPNS to point to that CID');
                console.log('   - Run this script again and choose Option 2');
                console.log('   - Provide: ipfs://Qm... or ipfs://ipns/your-ipns-name\n');
                console.log('='.repeat(60) + '\n');

                // Build data URI with chosen encoding
                const useBase64Encoding = useBase64.trim().toLowerCase() === 'y';
                if (useBase64Encoding) {
                    const base64Json = Buffer.from(jsonCompact, 'utf8').toString('base64');
                    finalUri = 'data:application/json;base64,' + base64Json;
                    console.log('✅ Generated contractURI: data URI with base64-encoded JSON (more compact)\n');
                } else {
                    finalUri = 'data:application/json;utf8,' + jsonCompact;
                    console.log('✅ Generated contractURI: data URI with UTF-8 encoded JSON (more readable)\n');
                }
            } else {
                console.log('\n⚠️  No description or image provided, using empty URI (default renderer)\n');
            }
        } else if (strategy === '2') {
            console.log('\n📎 Provide your existing contractURI...\n');
            console.log('Examples of valid URIs:');
            console.log('  • ipfs://QmYourHashHere');
            console.log('  • ipfs://ipns/k51qzi5uqu5dlj4rhdehyy6b71j1vo21syw4tgjhhrq2zc9afoblz98rjp4hau');
            console.log('  • https://ipfs.io/ipfs/QmYourHashHere');
            console.log('  • https://example.com/dao-metadata.json');
            console.log('  • data:application/json;utf8,{"name":"...","description":"..."}');
            console.log('  • data:image/svg+xml;base64,... (direct image)');
            console.log('');
            const uriInput = await question('Contract URI: ');
            finalUri = uriInput.trim();
            if (!finalUri) {
                console.log('\n⚠️  Empty URI provided, will use default renderer\n');
            } else {
                console.log(`\n✅ Using provided contractURI: ${finalUri.substring(0, 80)}${finalUri.length > 80 ? '...' : ''}\n`);
            }
        } else {
            // Option 3 or default
            console.log('\n✅ Using default renderer (Wyoming DUNA covenant card will be generated on-chain)\n');
            finalUri = '';
        }

        console.log('─'.repeat(60) + '\n');
        const proposalDescription = await question('Proposal Description (optional, for explaining the governance proposal): ');

        rl.close();

        const proposalData = await generateProposalData(
            finalDaoAddress,
            name.trim(),
            symbol.trim(),
            finalUri,
            proposalDescription.trim() || null,
            rpcUrl
        );

        displayProposalData(proposalData);

        // Show summary of what will be set
        console.log('─'.repeat(60));
        console.log('📋 SUMMARY OF WHAT WILL BE SET');
        console.log('─'.repeat(60));
        console.log(`Name: "${name.trim()}"`);
        console.log(`Symbol: "${symbol.trim()}"`);
        if (finalUri) {
            if (finalUri.startsWith('data:application/json')) {
                console.log(`Contract URI: data URI with embedded JSON (${finalUri.length} chars)`);
            } else if (finalUri.startsWith('data:')) {
                console.log(`Contract URI: ${finalUri.substring(0, 50)}...`);
            } else {
                console.log(`Contract URI: ${finalUri}`);
            }
        } else {
            console.log('Contract URI: (empty - default DUNA covenant card)');
        }
        console.log('─'.repeat(60) + '\n');
    } catch (error) {
        rl.close();
        throw error;
    }
}

/**
 * Parse --rpc flag from arguments
 * Returns { rpcUrl }
 */
function parseArgs(args) {
    let rpcUrl = null;

    for (let i = 0; i < args.length; i++) {
        if (args[i] === '--rpc' && i + 1 < args.length) {
            rpcUrl = args[i + 1];
            i++; // Skip the next argument (the URL)
        } else if (args[i] === '--help' || args[i] === '-h') {
            // Show usage and exit
            console.log('Usage: node set-dao-metadata.js [--rpc RPC_URL]');
            console.log('\nOptions:');
            console.log('  --rpc RPC_URL   Specify RPC endpoint URL');
            console.log('\nNote: RPC_URL can also be provided via RPC_URL environment variable');
            console.log('      If not provided, defaults to:', DEFAULT_RPC_URL);
            console.log('      The script runs in interactive mode and prompts for all values');
            process.exit(0);
        } else if (!args[i].startsWith('--')) {
            // Warn about unexpected positional arguments
            console.warn(`Warning: Unexpected argument "${args[i]}" ignored. Only --rpc is supported.`);
            console.warn('         All values should be entered interactively.\n');
        }
    }

    return { rpcUrl };
}

// CLI interface
async function main() {
    const args = process.argv.slice(2);

    // Parse --rpc flag
    let { rpcUrl } = parseArgs(args);

    // Check environment variable if --rpc not provided
    if (!rpcUrl) {
        rpcUrl = process.env.RPC_URL;
    }

    // Use default RPC URL if still not set
    if (!rpcUrl) {
        rpcUrl = DEFAULT_RPC_URL;
        console.log(`\nUsing default RPC URL: ${DEFAULT_RPC_URL}\n`);
    }

    try {
        // Always use interactive mode
        await interactiveMode(rpcUrl);
    } catch (error) {
        console.error('Error:', error.message);
        process.exit(1);
    }
}

// Run if executed directly
if (require.main === module) {
    main();
}

module.exports = { generateProposalData, displayProposalData };

