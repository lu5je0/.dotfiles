use std::{env, path::PathBuf, process::Command};

fn main() {
    println!("cargo:rerun-if-changed=src/macos.m");
    if env::var("CARGO_CFG_TARGET_OS").as_deref() != Ok("macos") {
        return;
    }
    let out = PathBuf::from(env::var_os("OUT_DIR").unwrap());
    let object = out.join("macos.o");
    let compiler = env::var("CC").unwrap_or_else(|_| "cc".into());
    let arch = if env::var("CARGO_CFG_TARGET_ARCH").as_deref() == Ok("aarch64") {
        "arm64"
    } else {
        "x86_64"
    };
    assert!(
        Command::new(compiler)
            .args(["-arch", arch, "-fobjc-arc", "-c", "src/macos.m", "-o"])
            .arg(&object)
            .status()
            .unwrap()
            .success()
    );
    assert!(
        Command::new(env::var("AR").unwrap_or_else(|_| "ar".into()))
            .arg("crs")
            .arg(out.join("libqtrash_mac.a"))
            .arg(object)
            .status()
            .unwrap()
            .success()
    );
    println!("cargo:rustc-link-search=native={}", out.display());
    println!("cargo:rustc-link-lib=static=qtrash_mac");
    println!("cargo:rustc-link-lib=framework=Foundation");
    println!("cargo:rustc-link-lib=objc");
}
