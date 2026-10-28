use std::collections::BTreeMap;
use std::env;
use std::fs::{self, File};
use std::io::{self, Read, Write};
use std::path::{Path, PathBuf};
use serde::{Deserialize, Serialize};

#[derive(Debug, Serialize, Deserialize)]
pub struct UnitFileMeta {
    pub relative_path: String,
    pub filename: String,
    pub unit_def_name: String,
    pub byte_size: u64,
    pub crc32: u32,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct CacheManifest {
    pub schema_version: u32,
    pub generator: String,
    pub composite_hash: String,
    pub total_units: usize,
    pub total_bytes: u64,
    pub gamedata_hashes: BTreeMap<String, u32>,
    pub units: Vec<UnitFileMeta>,
}

fn crc32_of_file(path: &Path) -> io::Result<(u32, u64)> {
    let mut file = File::open(path)?;
    let mut hasher = crc32fast::Hasher::new();
    let mut buffer = [0u8; 16384];
    let mut total_bytes = 0u64;

    loop {
        let count = file.read(&mut buffer)?;
        if count == 0 {
            break;
        }
        hasher.update(&buffer[..count]);
        total_bytes += count as u64;
    }

    Ok((hasher.finalize(), total_bytes))
}

fn collect_lua_files(dir: &Path, _base: &Path, out: &mut Vec<PathBuf>) -> io::Result<()> {
    if !dir.is_dir() {
        return Ok(());
    }
    for entry in fs::read_dir(dir)? {
        let entry = entry?;
        let path = entry.path();
        if path.is_dir() {
            collect_lua_files(&path, _base, out)?;
        } else if path.extension().and_then(|s| s.to_str()) == Some("lua") {
            out.push(path);
        }
    }
    Ok(())
}

fn extract_unit_def_name(filename: &str) -> String {
    let lower = filename.to_lowercase();
    let stem = lower.strip_suffix(".lua").unwrap_or(&lower);
    stem.to_string()
}

fn compute_composite_hash(units: &[UnitFileMeta], gamedata: &BTreeMap<String, u32>) -> String {
    let mut hasher = crc32fast::Hasher::new();
    hasher.update(b"BAR_UNITDEFS_CACHE_V2\n");

    for (k, v) in gamedata {
        hasher.update(k.as_bytes());
        hasher.update(&v.to_le_bytes());
    }

    for u in units {
        hasher.update(u.relative_path.as_bytes());
        hasher.update(&u.crc32.to_le_bytes());
        hasher.update(&u.byte_size.to_le_bytes());
    }

    format!("{:08x}", hasher.finalize())
}

fn build_cache(root: &Path) -> Result<(), Box<dyn std::error::Error>> {
    println!("\x1b[1;36m==================================================\x1b[0m");
    println!("\x1b[1;32m  BAR UnitDefs Cache Baker (Rust Edition)\x1b[0m");
    println!("\x1b[1;36m==================================================\x1b[0m");
    println!("Scanning repository at: {}", root.display());

    let units_dir = root.join("units");
    if !units_dir.exists() {
        return Err(format!("'units' directory not found in {}", root.display()).into());
    }

    let mut files = Vec::new();
    collect_lua_files(&units_dir, root, &mut files)?;
    files.sort();

    println!("Found {} unit definition files.", files.len());

    let mut unit_metas = Vec::with_capacity(files.len());
    let mut total_bytes = 0u64;

    for path in &files {
        let (crc, bytes) = crc32_of_file(path)?;
        total_bytes += bytes;

        let rel = path.strip_prefix(root).unwrap_or(path).to_slash_lossy();
        let fname = path.file_name().and_then(|s| s.to_str()).unwrap_or("").to_string();
        let def_name = extract_unit_def_name(&fname);

        unit_metas.push(UnitFileMeta {
            relative_path: rel,
            filename: fname,
            unit_def_name: def_name,
            byte_size: bytes,
            crc32: crc,
        });
    }

    // Check essential gamedata dependencies
    let mut gamedata_hashes = BTreeMap::new();
    let gamedata_deps = [
        "gamedata/unitdefs.lua",
        "gamedata/unitdefs_post.lua",
        "gamedata/alldefs_post.lua",
    ];

    for dep in &gamedata_deps {
        let p = root.join(dep);
        if p.exists() {
            let (crc, _) = crc32_of_file(&p)?;
            gamedata_hashes.insert(dep.to_string(), crc);
        }
    }

    let composite_hash = compute_composite_hash(&unit_metas, &gamedata_hashes);
    println!("Composite Hash: \x1b[1;33m{}\x1b[0m", composite_hash);

    let manifest = CacheManifest {
        schema_version: 2,
        generator: "bar-cache-baker-v0.1.0".to_string(),
        composite_hash: composite_hash.clone(),
        total_units: unit_metas.len(),
        total_bytes,
        gamedata_hashes,
        units: unit_metas,
    };

    let cache_dir = root.join("cache");
    fs::create_dir_all(&cache_dir)?;

    // 1. Write JSON manifest
    let manifest_json = serde_json::to_string_pretty(&manifest)?;
    let manifest_path = cache_dir.join("unitdefs_manifest.json");
    fs::write(&manifest_path, manifest_json)?;
    println!("Manifest written: {}", manifest_path.display());

    // 2. Write deterministic Lua cache file with embedded validation header
    let lua_path = cache_dir.join("unitdefs_cache.lua");
    let mut lua_out = File::create(&lua_path)?;

    writeln!(lua_out, "--[[")?;
    writeln!(lua_out, "  AUTOMATICALLY GENERATED BY bar-cache-baker")?;
    writeln!(lua_out, "  CACHE_HASH: {}", composite_hash)?;
    writeln!(lua_out, "  TOTAL_UNITS: {}", manifest.total_units)?;
    writeln!(lua_out, "  TOTAL_BYTES: {}", manifest.total_bytes)?;
    writeln!(lua_out, "]]")?;
    writeln!(lua_out, "local cache = {{")?;
    writeln!(lua_out, "  hash = \"{}\",", composite_hash)?;
    writeln!(lua_out, "  totalUnits = {},", manifest.total_units)?;
    writeln!(lua_out, "  unitPaths = {{")?;

    for u in &manifest.units {
        writeln!(
            lua_out,
            "    [\"{}\"] = \"{}\",",
            u.unit_def_name, u.relative_path
        )?;
    }

    writeln!(lua_out, "  }},")?;
    writeln!(lua_out, "  unitList = {{")?;

    for u in &manifest.units {
        writeln!(lua_out, "    \"{}\",", u.relative_path)?;
    }

    writeln!(lua_out, "  }},")?;
    writeln!(lua_out, "}}")?;
    writeln!(lua_out, "return cache")?;

    println!("Lua cache index written: {}", lua_path.display());
    println!("\x1b[1;32mCache bake completed successfully!\x1b[0m");

    Ok(())
}

trait PathExt {
    fn to_slash_lossy(&self) -> String;
}

impl PathExt for Path {
    fn to_slash_lossy(&self) -> String {
        self.to_string_lossy().replace('\\', "/")
    }
}

fn main() {
    let args: Vec<String> = env::args().collect();
    let root = if args.len() > 1 {
        PathBuf::from(&args[1])
    } else {
        PathBuf::from(".")
    };

    if let Err(e) = build_cache(&root) {
        eprintln!("\x1b[1;31mError building cache:\x1b[0m {}", e);
        std::process::exit(1);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_extract_unit_def_name() {
        assert_eq!(extract_unit_def_name("armcom.lua"), "armcom");
        assert_eq!(extract_unit_def_name("CORCOM.LUA"), "corcom");
        assert_eq!(extract_unit_def_name("arm_zeus.lua"), "arm_zeus");
    }

    #[test]
    fn test_composite_hash_determinism() {
        let mut gamedata = BTreeMap::new();
        gamedata.insert("gamedata/unitdefs.lua".to_string(), 12345);
        gamedata.insert("gamedata/unitdefs_post.lua".to_string(), 67890);

        let units = vec![
            UnitFileMeta {
                relative_path: "units/armcom.lua".to_string(),
                filename: "armcom.lua".to_string(),
                unit_def_name: "armcom".to_string(),
                byte_size: 4096,
                crc32: 0xDEADBEEF,
            },
            UnitFileMeta {
                relative_path: "units/corcom.lua".to_string(),
                filename: "corcom.lua".to_string(),
                unit_def_name: "corcom".to_string(),
                byte_size: 4120,
                crc32: 0xCAFEBABE,
            },
        ];

        let hash1 = compute_composite_hash(&units, &gamedata);
        let hash2 = compute_composite_hash(&units, &gamedata);
        assert_eq!(hash1, hash2);
        assert_eq!(hash1.len(), 8);
    }
}
