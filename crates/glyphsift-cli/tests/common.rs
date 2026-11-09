//! Shared helpers for the CLI integration tests: run the binary, feed stdin, collect the result.
#![allow(dead_code)]

use std::io::Write;
use std::process::{Command, Stdio};

pub struct Run {
    pub code: i32,
    pub stdout: Vec<u8>,
    pub stderr: String,
}

impl Run {
    pub fn out(&self) -> String {
        String::from_utf8(self.stdout.clone()).expect("stdout is UTF-8")
    }
}

pub fn run(args: &[&str], stdin: &[u8]) -> Run {
    let mut child = Command::new(env!("CARGO_BIN_EXE_glyphsift"))
        .args(args)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .expect("spawn glyphsift");
    {
        let mut pipe = child.stdin.take().expect("stdin pipe");
        // The child may exit before reading everything (bad arguments); that is not an error here.
        let _ = pipe.write_all(stdin);
    }
    let output = child.wait_with_output().expect("wait for glyphsift");
    Run {
        code: output.status.code().expect("exit code"),
        stdout: output.stdout,
        stderr: String::from_utf8_lossy(&output.stderr).into_owned(),
    }
}

pub fn corpus() -> String {
    let path =
        std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../../bench/corpus/clean.txt");
    std::fs::read_to_string(path).expect("bench/corpus/clean.txt")
}

pub fn scratch(name: &str) -> std::path::PathBuf {
    let dir = std::path::Path::new(env!("CARGO_TARGET_TMPDIR")).join(name);
    std::fs::create_dir_all(&dir).expect("create scratch dir");
    dir
}
