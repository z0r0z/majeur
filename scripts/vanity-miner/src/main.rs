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
//!     [--threads N]
//!
//! Or pass raw init code instead of its hash:
//!   --init-code 0x<bytecode>

use rayon::prelude::*;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::time::Instant;
use tiny_keccak::{Hasher, Keccak};

fn keccak256(data: &[u8]) -> [u8; 32] {
    let mut hasher = Keccak::v256();
    let mut output = [0u8; 32];
    hasher.update(data);
    hasher.finalize(&mut output);
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

fn matches_prefix(addr: &[u8; 20], prefix: &[u8]) -> bool {
    addr[..prefix.len()] == *prefix
}

fn main() {
    let args: Vec<String> = std::env::args().collect();

    let mut deployer_str = String::new();
    let mut init_code_hash_str = String::new();
    let mut init_code_str = String::new();
    let mut prefix_str = String::from("00000000");
    let mut caller_str = String::new();
    let mut threads: usize = 0; // 0 = auto

    let mut i = 1;
    while i < args.len() {
        match args[i].as_str() {
            "--deployer" => {
                deployer_str = args[i + 1].clone();
                i += 2;
            }
            "--init-code-hash" => {
                init_code_hash_str = args[i + 1].clone();
                i += 2;
            }
            "--init-code" => {
                init_code_str = args[i + 1].clone();
                i += 2;
            }
            "--prefix" => {
                prefix_str = args[i + 1].clone();
                i += 2;
            }
            "--caller" => {
                caller_str = args[i + 1].clone();
                i += 2;
            }
            "--threads" => {
                threads = args[i + 1].parse().expect("invalid thread count");
                i += 2;
            }
            other => {
                eprintln!("unknown arg: {other}");
                std::process::exit(1);
            }
        }
    }

    assert!(!deployer_str.is_empty(), "missing --deployer");
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

    // Each thread works on its own range: thread_id, thread_id + num_threads, ...
    let result: Option<(u64, [u8; 32], [u8; 20])> = (0..num_threads)
        .into_par_iter()
        .find_map_any(|thread_id| {
            let mut buf = template;
            let mut nonce = thread_id as u64;

            loop {
                if found.load(Ordering::Relaxed) {
                    return None;
                }

                // Build salt
                let salt = if use_caller {
                    // keccak256(caller ++ nonce) for front-run protection
                    let mut pre = [0u8; 52]; // 20 + 32
                    pre[..20].copy_from_slice(&caller);
                    pre[20..52].copy_from_slice(&nonce.to_be_bytes().iter().copied()
                        .chain(std::iter::repeat(0).take(24))
                        .collect::<Vec<_>>());
                    // Actually: pad nonce to 32 bytes (right-aligned)
                    let mut nonce_bytes = [0u8; 32];
                    nonce_bytes[24..].copy_from_slice(&nonce.to_be_bytes());
                    pre[20..52].copy_from_slice(&nonce_bytes);
                    keccak256(&pre)
                } else {
                    let mut s = [0u8; 32];
                    s[24..].copy_from_slice(&nonce.to_be_bytes());
                    s
                };

                buf[21..53].copy_from_slice(&salt);

                let hash = keccak256(&buf);
                let mut addr = [0u8; 20];
                addr.copy_from_slice(&hash[12..32]);

                if matches_prefix(&addr, &prefix) {
                    found.store(true, Ordering::Relaxed);
                    return Some((nonce, salt, addr));
                }

                // Progress reporting every ~10M per thread
                let old = counter.fetch_add(1, Ordering::Relaxed);
                if old % 10_000_000 == 0 && old > 0 {
                    let elapsed = start.elapsed().as_secs_f64();
                    let rate = old as f64 / elapsed;
                    eprintln!(
                        "[{:.1}s] {:.0}M hashes | {:.1}M/s",
                        elapsed,
                        old as f64 / 1e6,
                        rate / 1e6
                    );
                }

                nonce += num_threads as u64;
                // Safety: stop at u64::MAX (won't happen in practice)
                if nonce < thread_id as u64 {
                    return None;
                }
            }
        });

    let elapsed = start.elapsed().as_secs_f64();
    let total = counter.load(Ordering::Relaxed);

    match result {
        Some((nonce, salt, addr)) => {
            eprintln!();
            eprintln!("FOUND in {:.2}s ({total} hashes, {:.1}M/s)", elapsed, total as f64 / elapsed / 1e6);
            eprintln!("  nonce:   {nonce}");
            eprintln!("  salt:    0x{}", hex::encode(salt));
            eprintln!("  address: 0x{}", hex::encode(addr));
            // Machine-readable output on stdout
            println!("0x{}", hex::encode(salt));
        }
        None => {
            eprintln!("No match found after {total} hashes ({elapsed:.2}s)");
            std::process::exit(1);
        }
    }
}
