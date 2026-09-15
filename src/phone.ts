export const phoneCountries = [
  {code: '+91', label: '🇮🇳 India (+91)', placeholder: '98765 43210', pattern: /^[6-9][0-9]{9}$/},
  {code: '+971', label: '🇦🇪 UAE (+971)', placeholder: '50 123 4567', pattern: /^5[0-9]{8}$/},
  {code: '+966', label: '🇸🇦 Saudi Arabia (+966)', placeholder: '50 123 4567', pattern: /^5[0-9]{8}$/},
  {code: '+974', label: '🇶🇦 Qatar (+974)', placeholder: '5512 3456', pattern: /^[0-9]{8}$/},
  {code: '+968', label: '🇴🇲 Oman (+968)', placeholder: '9212 3456', pattern: /^[0-9]{8}$/},
  {code: '+965', label: '🇰🇼 Kuwait (+965)', placeholder: '5512 3456', pattern: /^[0-9]{8}$/},
  {code: '+973', label: '🇧🇭 Bahrain (+973)', placeholder: '3312 3456', pattern: /^[0-9]{8}$/},
];

// Format checking only. Approval separately confirms control of the number.
export function normalizePhone(country: string, input: string): string | null {
  const selected = phoneCountries.find(c => c.code === country);
  let raw = input.trim();
  if (!selected || !raw || !/^[+0-9\s().-]+$/.test(raw)) return null;
  if (raw.startsWith('00')) raw = '+' + raw.slice(2);
  let digits = raw.replace(/[\s().-]/g, '');
  if (digits.startsWith('+')) {
    if (!digits.startsWith(country)) return null;
    digits = digits.slice(country.length);
  } else if ((country === '+91' || country === '+971' || country === '+966') && digits.startsWith('0')) {
    digits = digits.slice(1);
  }
  return selected.pattern.test(digits) ? country + digits : null;
}

export function safeReturnUrl(value: string | null): string {
  if (!value || !value.startsWith('/') || value.startsWith('//') || /[\\\x00-\x20]/.test(value)) return '/';
  return value;
}
