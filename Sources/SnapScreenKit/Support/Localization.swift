import Foundation

/// SnapScreenKit 모듈 번들에서 로컬라이즈한다.
/// 키는 사용자에게 보일 영어 문장 그대로이며, 보간은 String.LocalizationValue가
/// 포맷 키(%lld/%@)로 변환한다. 번역은 Resources/{en,ko}.lproj/Localizable.strings.
func L(_ key: String.LocalizationValue) -> String {
    String(localized: key, bundle: .module)
}
