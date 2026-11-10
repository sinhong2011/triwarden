/**
 * Whether a fill should ask the app to put the one-time code on the clipboard.
 * Always sent as `copyTotp` on `fill`: `true` copies when Settings › Browser has the option on
 * and the login has a code; `false` skips because an OTP field on this page takes the code instead.
 */
export function shouldRequestTotpCopy(filledOtpOnPage: boolean): boolean {
  return !filledOtpOnPage;
}
