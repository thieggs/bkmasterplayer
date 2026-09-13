//! Lista dispositivos de saída como o app vê. Uso: cargo run --example devices
use cpal::traits::{DeviceTrait, HostTrait};
fn main() -> anyhow::Result<()> {
    for d in player_engine::engine::output::list_devices()? {
        println!("{:<5} {:<40} {}", if d.is_default { "PADR" } else { "" }, d.id, d.name);
    }
    let host = cpal::default_host();
    let dev = host.default_output_device().unwrap();
    let cfg = dev.default_output_config()?;
    println!("padrão: {:?} buffer {:?}", cfg.sample_rate(), cfg.buffer_size());
    for c in dev.supported_output_configs()? { println!("  suporta {:?}", c); }
    Ok(())
}
