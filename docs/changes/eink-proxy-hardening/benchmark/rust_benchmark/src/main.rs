// Rust prototype benchmark mirroring scripts/benchmark_hotspots.dart
// (REQ-013, TASK-401). Run with: cargo run --release
use md5::{Digest, Md5};
use std::fs;
use std::time::Instant;
use walkdir::WalkDir;

fn measure<F: FnMut(usize)>(name: &str, iterations: usize, mut body: F) {
    body(usize::MAX); // warmup
    let start = Instant::now();
    for i in 0..iterations {
        body(i);
    }
    let elapsed = start.elapsed();
    println!(
        "{}: total {:?} / {} ops = {:.2} µs/op",
        name,
        elapsed,
        iterations,
        elapsed.as_micros() as f64 / iterations as f64
    );
}

fn main() {
    println!("== EZVenera hotspot prototype — Rust (release) ==");

    // H1 — cache key md5
    let key_sample = "v2|ecchiw|e0a1f2|cb3aa919|https://img.example.com/pages/0123.jpg?p=1";
    measure("H1 md5 cache key", 20000, |i| {
        let mut hasher = Md5::new();
        hasher.update(format!("{}|{}", key_sample, i).as_bytes());
        let _ = hasher.finalize();
    });

    // H2 — cache trim scan (2000 files, 64 subdirs)
    let dir = std::env::temp_dir().join("ezv_bench_cache_rust");
    let _ = fs::remove_dir_all(&dir);
    for i in 0..2000 {
        let sub = dir.join(format!("{:x}", i % 64));
        fs::create_dir_all(&sub).unwrap();
        fs::write(sub.join(format!("{}.bin", i)), vec![0u8; 2048]).unwrap();
    }
    measure("H2 cache trim scan (stat+sort, 2000 files)", 5, |_| {
        let mut entries: Vec<(std::path::PathBuf, u64, std::time::SystemTime)> =
            Vec::new();
        for entry in WalkDir::new(&dir).into_iter().filter_map(|e| e.ok()) {
            if entry.file_type().is_file() {
                let meta = entry.metadata().unwrap();
                entries.push((
                    entry.into_path(),
                    meta.len(),
                    meta.modified().unwrap(),
                ));
            }
        }
        entries.sort_by_key(|(_, _, m)| *m);
    });
    let _ = fs::remove_dir_all(&dir);

    // H3 — pixel ops on a 1200x1800 RGBA (u32) comic page
    const W: usize = 1200;
    const H: usize = 1800;
    let mut page = vec![0u32; W * H];
    let mut rng: u32 = 0x12345678;
    for px in page.iter_mut() {
        rng = rng.wrapping_mul(1103515245).wrapping_add(12345) & 0x7FFFFFFF;
        *px = rng;
    }
    measure("H3 copyAndRotate90 (1200x1800)", 20, |_| {
        let mut out = vec![0u32; W * H];
        for y in 0..H {
            for x in 0..W {
                out[x * H + H - y - 1] = page[y * W + x];
            }
        }
        std::hint::black_box(&out);
    });
    measure("H3 copyRange (600x900 region)", 40, |_| {
        let mut out = vec![0u32; 600 * 900];
        for y in 0..900 {
            for x in 0..600 {
                out[y * 600 + x] = page[(y + 100) * W + x + 50];
            }
        }
        std::hint::black_box(&out);
    });

    println!("== done ==");
}
