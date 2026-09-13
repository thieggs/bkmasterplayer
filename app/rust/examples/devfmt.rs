use cpal::traits::{DeviceTrait, HostTrait};
fn main() {
    let host = cpal::default_host();
    let d = host.default_output_device().unwrap();
    println!("default id: {:?}", d.id().map(|i| i.to_string()));
    println!("default config: {:?}", d.default_output_config());
    println!("hosts: {:?}", cpal::available_hosts());
}
