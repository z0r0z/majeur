/**
 * Generate Proposal Data for Setting DAO Metadata
 *
 * This script generates the inputs needed to create a governance proposal
 * to update DAO metadata (name, symbol, contractURI).
 *
 * Note: The URI parameter is the DAO emblem (image) URL, typically an IPFS/IPNS URL
 * like "https://ipfs.io/ipns/..." or "https://ipfs.io/ipfs/...".
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
 *   The script runs in interactive mode and will prompt for all required values:
 *   - DAO Address
 *   - DAO Name
 *   - DAO Symbol
 *   - DAO Emblem URL (optional)
 *   - Description (optional)
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
        description: description || `Update DAO metadata: name="${name}", symbol="${symbol}", emblem="${uri}"`
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
    console.log('\n📋 Use these values in your UI:\n');

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

    console.log('DESCRIPTION:');
    console.log(`  ${proposalData.description}\n`);

    console.log('─'.repeat(60));
    console.log('Additional Information:\n');

    console.log('Operation Type:');
    console.log(`  ${proposalData.op} (0 = call, 1 = delegatecall)\n`);

    console.log('Nonce (bytes32):');
    console.log(`  ${proposalData.nonce}\n`);

    if (proposalData.proposalId) {
        console.log('Proposal ID (calculated):');
        console.log(`  ${proposalData.proposalId.toString()}\n`);
    }

    console.log('='.repeat(60));
    console.log('\n💡 Tip: You can use this nonce to calculate the proposal ID');
    console.log('   before creating the proposal, or use a custom nonce.\n');
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

        const uri = await question('DAO Emblem URL (image, e.g., https://ipfs.io/ipns/..., optional, press Enter to skip): ');
        const description = await question('Description (optional, press Enter for default): ');

        rl.close();

        const proposalData = await generateProposalData(
            finalDaoAddress,
            name.trim(),
            symbol.trim(),
            uri.trim() || '',
            description.trim() || null,
            rpcUrl
        );

        displayProposalData(proposalData);
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

