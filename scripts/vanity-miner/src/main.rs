//! Vanity CREATE2 address miner for SafeSummoner.create2Deploy.
//!
//! Mines a `bytes32 salt` such that:
//!   address = keccak256(0xff ++ deployer ++ salt ++ initCodeHash)[12..]
//! starts with the desired prefix bytes.
//!
//! Usage:
//!   cargo run --release -- \
//!     --deployer 0x<SafeSummoner> \
//!     --init-code-hash 0x<hash>  \
//!     --prefix 00000000 \
//!     [--caller 0x<addr>] \
//!     [--output results.json] \
//!     [--threads N]
//!
//! Or pass raw init code instead of its hash:
//!   --init-code 0x<bytecode>

use digest::Digest;
use keccak_asm::Keccak256;
use rayon::prelude::*;
use serde::{Deserialize, Serialize};
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::time::Instant;

#[derive(Serialize, Deserialize)]
struct VanityResult {
    timestamp: String,
    deployer: String,
    init_code_hash: String,
    prefix: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    caller: Option<String>,
    nonce: u64,
    salt: String,
    address: String,
    elapsed_secs: f64,
    total_hashes: u64,
}

fn keccak256(data: &[u8]) -> [u8; 32] {
    let mut hasher = Keccak256::new();
    hasher.update(data);
    let result = hasher.finalize();
    let mut output = [0u8; 32];
    output.copy_from_slice(&result);
    output
}

fn parse_hex(s: &str) -> Vec<u8> {
    let s = s.strip_prefix("0x").unwrap_or(s);
    hex::decode(s).expect("invalid hex")
}

fn parse_address(s: &str) -> [u8; 20] {
    let bytes = parse_hex(s);
    assert_eq!(bytes.len(), 20, "address must be 20 bytes");
    let mut arr = [0u8; 20];
    arr.copy_from_slice(&bytes);
    arr
}

fn parse_bytes32(s: &str) -> [u8; 32] {
    let bytes = parse_hex(s);
    assert_eq!(bytes.len(), 32, "expected 32 bytes");
    let mut arr = [0u8; 32];
    arr.copy_from_slice(&bytes);
    arr
}

fn main() {
    let args: Vec<String> = std::env::args().collect();

    let mut deployer_str = String::new();
    let mut init_code_hash_str = String::new();
    let mut init_code_str = String::new();
    let mut prefix_str = String::from("00000000");
    let mut caller_str = String::new();
    // Default output: scripts/vanity-miner/results/ relative to the binary
    let mut output_str = std::env::current_exe()
        .ok()
        .and_then(|p| p.parent()?.parent()?.parent().map(|p| p.to_path_buf()))
        .map(|p| p.join("results").join("results.json").to_string_lossy().into_owned())
        .unwrap_or_else(|| "vanity-results.json".to_string());
    let mut threads: usize = 0; // 0 = auto

    // Parse args: support both --flag value and env var fallback
    let mut i = 1;
    while i < args.len() {
        let arg = args[i].as_str();
        match arg {
            "-d" | "--deployer" => { deployer_str = args[i + 1].clone(); i += 2; }
            "-h" | "--init-code-hash" => { init_code_hash_str = args[i + 1].clone(); i += 2; }
            "-i" | "--init-code" => { init_code_str = args[i + 1].clone(); i += 2; }
            "-p" | "--prefix" => { prefix_str = args[i + 1].clone(); i += 2; }
            "-c" | "--caller" => { caller_str = args[i + 1].clone(); i += 2; }
            "-o" | "--output" => { output_str = args[i + 1].clone(); i += 2; }
            "-t" | "--threads" => { threads = args[i + 1].parse().expect("invalid thread count"); i += 2; }
            other => { eprintln!("unknown arg: {other}"); std::process::exit(1); }
        }
    }

    // Env var fallback
    if deployer_str.is_empty() { deployer_str = std::env::var("DEPLOYER").unwrap_or_default(); }
    if init_code_str.is_empty() { init_code_str = std::env::var("INIT_CODE").unwrap_or_default(); }
    if init_code_hash_str.is_empty() { init_code_hash_str = std::env::var("INIT_CODE_HASH").unwrap_or_default(); }
    if prefix_str == "00000000" { prefix_str = std::env::var("PREFIX").unwrap_or(prefix_str); }
    if caller_str.is_empty() { caller_str = std::env::var("CALLER").unwrap_or_default(); }

    assert!(!deployer_str.is_empty(), "missing --deployer / DEPLOYER");
    assert!(
        !init_code_hash_str.is_empty() || !init_code_str.is_empty(),
        "need --init-code-hash or --init-code"
    );

    let deployer = parse_address(&deployer_str);
    let init_code_hash = if !init_code_hash_str.is_empty() {
        parse_bytes32(&init_code_hash_str)
    } else {
        keccak256(&parse_hex(&init_code_str))
    };
    let prefix = parse_hex(&prefix_str);
    assert!(prefix.len() <= 20, "prefix too long");

    let use_caller = !caller_str.is_empty();
    let caller = if use_caller {
        parse_address(&caller_str)
    } else {
        [0u8; 20]
    };

    if threads > 0 {
        rayon::ThreadPoolBuilder::new()
            .num_threads(threads)
            .build_global()
            .unwrap();
    }
    let num_threads = rayon::current_num_threads();

    eprintln!("=== VanityMiner (Rust) ===");
    eprintln!("Deployer:       0x{}", hex::encode(deployer));
    eprintln!("InitCodeHash:   0x{}", hex::encode(init_code_hash));
    eprintln!("Prefix:         0x{}", hex::encode(&prefix));
    eprintln!(
        "Difficulty:     ~{:.1e} expected tries ({} leading hex chars)",
        16f64.powi(prefix_str.len() as i32),
        prefix_str.len()
    );
    if use_caller {
        eprintln!("Caller:         0x{}", hex::encode(caller));
    }
    eprintln!("Threads:        {num_threads}");
    eprintln!();

    // Pre-build the static portion: 0xff ++ deployer ++ [salt placeholder] ++ initCodeHash
    // Total = 1 + 20 + 32 + 32 = 85 bytes
    let mut template = [0u8; 85];
    template[0] = 0xff;
    template[1..21].copy_from_slice(&deployer);
    // [21..53] = salt (filled per iteration)
    template[53..85].copy_from_slice(&init_code_hash);

    let found = AtomicBool::new(false);
    let counter = AtomicU64::new(0);
    let start = Instant::now();

    // Build a prefix mask for fast integer comparison instead of byte-by-byte
    let prefix_len = prefix.len();
    let mut prefix_u32 = 0u32;
    let mut mask_u32 = 0u32;
    if prefix_len <= 4 {
        for (i, &b) in prefix.iter().enumerate() {
            prefix_u32 |= (b as u32) << (24 - i * 8);
            mask_u32 |= 0xFF << (24 - i * 8);
        }
    }

    // Pre-build caller hash prefix for the caller path (static portion)
    let mut caller_pre = [0u8; 52]; // 20 + 32
    if use_caller {
        caller_pre[..20].copy_from_slice(&caller);
    }

    const BATCH: u64 = 4096;
    let step = num_threads as u64;

    // Each thread works on its own range: thread_id, thread_id + num_threads, ...
    let result: Option<(u64, [u8; 32], [u8; 20])> = (0..num_threads)
        .into_par_iter()
        .find_map_any(|thread_id| {
            let mut buf = template;
            let mut nonce = thread_id as u64;
            let mut local_count = 0u64;

            loop {
                // Check termination and report progress in batches
                if local_count % BATCH == 0 {
                    if found.load(Ordering::Relaxed) {
                        counter.fetch_add(local_count, Ordering::Relaxed);
                        return None;
                    }
                    if local_count > 0 && local_count % (BATCH * 2048) == 0 {
                        let total = counter.fetch_add(local_count, Ordering::Relaxed) + local_count;
                        local_count = 0;
                        let elapsed = start.elapsed().as_secs_f64();
                        if thread_id == 0 {
                            eprintln!(
                                "[{:.1}s] {:.0}M hashes | {:.1}M/s",
                                elapsed,
                                total as f64 / 1e6,
                                total as f64 / elapsed / 1e6
                            );
                        }
                    }
                }

                // Build salt directly into buf
                if use_caller {
                    let mut pre = caller_pre;
                    pre[44..52].copy_from_slice(&nonce.to_be_bytes());
                    // pre[20..44] already zeroed from init
                    buf[21..53].copy_from_slice(&keccak256(&pre));
                } else {
                    // Write nonce directly into buf at the salt position (last 8 bytes of salt)
                    buf[45..53].copy_from_slice(&nonce.to_be_bytes());
                }

                let hash = keccak256(&buf);

                // Fast prefix match: u32 comparison for prefixes <= 4 bytes
                let hit = if prefix_len <= 4 {
                    let addr_head = u32::from_be_bytes([hash[12], hash[13], hash[14], hash[15]]);
                    (addr_head & mask_u32) == prefix_u32
                } else {
                    hash[12..12 + prefix_len] == *prefix
                };

                if hit {
                    found.store(true, Ordering::Relaxed);
                    counter.fetch_add(local_count, Ordering::Relaxed);
                    let mut salt = [0u8; 32];
                    salt.copy_from_slice(&buf[21..53]);
                    let mut addr = [0u8; 20];
                    addr.copy_from_slice(&hash[12..32]);
                    return Some((nonce, salt, addr));
                }

                local_count += 1;
                nonce += step;
                if nonce < thread_id as u64 {
                    counter.fetch_add(local_count, Ordering::Relaxed);
                    return None;
                }
            }
        });

    let elapsed = start.elapsed().as_secs_f64();
    let total = counter.load(Ordering::Relaxed);

    match result {
        Some((nonce, salt, addr)) => {
            let salt_hex = format!("0x{}", hex::encode(salt));
            let addr_hex = format!("0x{}", hex::encode(addr));

            eprintln!();
            eprintln!("FOUND in {:.2}s ({total} hashes, {:.1}M/s)", elapsed, total as f64 / elapsed / 1e6);
            eprintln!("  nonce:   {nonce}");
            eprintln!("  salt:    {salt_hex}");
            eprintln!("  address: {addr_hex}");

            // Save to JSON file (append to existing array or create new)
            let entry = VanityResult {
                timestamp: chrono::Utc::now().to_rfc3339(),
                deployer: format!("0x{}", hex::encode(deployer)),
                init_code_hash: format!("0x{}", hex::encode(init_code_hash)),
                prefix: prefix_str.clone(),
                caller: if use_caller { Some(format!("0x{}", hex::encode(caller))) } else { None },
                nonce,
                salt: salt_hex.clone(),
                address: addr_hex.clone(),
                elapsed_secs: elapsed,
                total_hashes: total,
            };

            let output_path = std::path::Path::new(&output_str);
            if let Some(parent) = output_path.parent() {
                let _ = std::fs::create_dir_all(parent);
            }

            let mut results: Vec<VanityResult> = std::fs::read_to_string(&output_str)
                .ok()
                .and_then(|s| serde_json::from_str(&s).ok())
                .unwrap_or_default();
            results.push(entry);

            match std::fs::write(&output_str, serde_json::to_string_pretty(&results).unwrap()) {
                Ok(_) => eprintln!("  saved:   {output_str}"),
                Err(e) => eprintln!("  warning: failed to save {output_str}: {e}"),
            }

            // Machine-readable output on stdout
            println!("{salt_hex}");
        }
        None => {
            eprintln!("No match found after {total} hashes ({elapsed:.2}s)");
            std::process::exit(1);
        }
    }
}
