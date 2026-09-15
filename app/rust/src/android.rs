//! Ponte com o Android. O Dart abre esta biblioteca pelo FFI (dlopen), que não
//! entrega a JVM a ninguém; o cpal (AAudio) precisa dela e do Context do app
//! para abrir o áudio. Por isso o app Android carrega a biblioteca antes pelo
//! `System.loadLibrary` (que chama o `JNI_OnLoad`) e entrega o Context em
//! `initNative`. O dlopen do Dart depois reaproveita a mesma cópia carregada.

use std::ffi::c_void;
use std::sync::atomic::{AtomicPtr, Ordering};

use jni_sys::{jint, jobject, JNIEnv, JavaVM, JNI_VERSION_1_6};

static VM: AtomicPtr<JavaVM> = AtomicPtr::new(std::ptr::null_mut());

#[no_mangle]
pub extern "system" fn JNI_OnLoad(vm: *mut JavaVM, _reserved: *mut c_void) -> jint {
    VM.store(vm, Ordering::SeqCst);
    JNI_VERSION_1_6
}

/// `BkApplication.initNative(context)`: guarda a JVM e o Context (referência
/// global, vale enquanto o processo viver) para o ndk-context.
#[no_mangle]
pub extern "system" fn Java_io_github_playermusica_player_1musica_BkApplication_initNative(
    env: *mut JNIEnv,
    _this: jobject,
    context: jobject,
) {
    let vm = VM.load(Ordering::SeqCst);
    if vm.is_null() || env.is_null() || context.is_null() {
        return;
    }
    // SAFETY: env, vm e context vêm da JVM nesta chamada JNI e foram checados
    // (não nulos); a referência global mantém o Context vivo para o ndk_context.
    unsafe {
        let Some(new_global_ref) = (**env).NewGlobalRef else { return };
        let global = new_global_ref(env, context);
        if !global.is_null() {
            ndk_context::initialize_android_context(vm.cast(), global.cast());
        }
    }
}
