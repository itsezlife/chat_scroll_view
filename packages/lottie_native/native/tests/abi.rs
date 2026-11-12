use chat_lottie::chat_lottie_abi_version;

#[test]
fn abi_version_is_one() {
    assert_eq!(chat_lottie_abi_version(), 1);
}
