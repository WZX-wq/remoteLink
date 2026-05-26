use std::{env, fs, path::Path};

use base64::{engine::general_purpose::STANDARD, Engine as _};
use sodiumoxide::crypto::sign;

fn usage() -> ! {
    eprintln!(
        "Usage:\n  custom_client_signer gen-key\n  custom_client_signer sign <config.json> <secret-key-base64> [custom.txt]\n  custom_client_signer verify <custom.txt> <public-key-base64> [config.json]"
    );
    std::process::exit(2);
}

fn encode64<T: AsRef<[u8]>>(input: T) -> String {
    STANDARD.encode(input)
}

fn decode64<T: AsRef<[u8]>>(input: T) -> Vec<u8> {
    STANDARD.decode(input).unwrap_or_else(|err| {
        eprintln!("Failed to decode base64: {err}");
        std::process::exit(1);
    })
}

fn gen_key() {
    let (pk, sk) = sign::gen_keypair();
    println!("public-key={}", encode64(pk.0));
    println!("secret-key={}", encode64(sk.0));
}

fn sign_config(input: &Path, secret_key_base64: &str, output: &Path) {
    let sk_bytes = decode64(secret_key_base64.trim());
    let Some(sk) = sign::SecretKey::from_slice(&sk_bytes) else {
        eprintln!(
            "Invalid secret key length, expected {} bytes",
            sign::SECRETKEYBYTES
        );
        std::process::exit(1);
    };
    let body = fs::read(input).unwrap_or_else(|err| {
        eprintln!("Failed to read {}: {err}", input.display());
        std::process::exit(1);
    });
    if let Err(err) = serde_json::from_slice::<serde_json::Value>(&body) {
        eprintln!("Invalid JSON in {}: {err}", input.display());
        std::process::exit(1);
    }
    let signed = sign::sign(&body, &sk);
    fs::write(output, encode64(signed)).unwrap_or_else(|err| {
        eprintln!("Failed to write {}: {err}", output.display());
        std::process::exit(1);
    });
    println!("Wrote signed custom client config to {}", output.display());
}

fn verify_config(input: &Path, public_key_base64: &str, expected_json: Option<&Path>) {
    let pk_bytes = decode64(public_key_base64.trim());
    let Some(pk) = sign::PublicKey::from_slice(&pk_bytes) else {
        eprintln!(
            "Invalid public key length, expected {} bytes",
            sign::PUBLICKEYBYTES
        );
        std::process::exit(1);
    };
    let signed = fs::read_to_string(input).unwrap_or_else(|err| {
        eprintln!("Failed to read {}: {err}", input.display());
        std::process::exit(1);
    });
    let signed = decode64(signed.trim());
    let raw = sign::verify(&signed, &pk).unwrap_or_else(|_| {
        eprintln!("Signature verification failed for {}", input.display());
        std::process::exit(1);
    });
    if let Err(err) = serde_json::from_slice::<serde_json::Value>(&raw) {
        eprintln!("Signed payload is not valid JSON: {err}");
        std::process::exit(1);
    }
    if let Some(expected_json) = expected_json {
        let expected = fs::read(expected_json).unwrap_or_else(|err| {
            eprintln!("Failed to read {}: {err}", expected_json.display());
            std::process::exit(1);
        });
        if raw != expected {
            eprintln!(
                "Verified payload does not match {}",
                expected_json.display()
            );
            std::process::exit(1);
        }
    }
    println!("Verified signed custom client config {}", input.display());
}

fn main() {
    if sodiumoxide::init().is_err() {
        eprintln!("Failed to initialize sodiumoxide");
        std::process::exit(1);
    }

    let args = env::args().collect::<Vec<_>>();
    match args.get(1).map(|x| x.as_str()) {
        Some("gen-key") if args.len() == 2 => gen_key(),
        Some("sign") if args.len() == 4 || args.len() == 5 => {
            let output = args
                .get(4)
                .map(|s| Path::new(s.as_str()))
                .unwrap_or_else(|| Path::new("custom.txt"));
            sign_config(Path::new(&args[2]), &args[3], output);
        }
        Some("verify") if args.len() == 4 || args.len() == 5 => {
            let expected_json = args.get(4).map(|s| Path::new(s.as_str()));
            verify_config(Path::new(&args[2]), &args[3], expected_json);
        }
        _ => usage(),
    }
}
