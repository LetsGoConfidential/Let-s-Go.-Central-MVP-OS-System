export function isOneOf<const Options extends readonly string[]>(options: Options, value: string): value is Options[number] {
  return (options as readonly string[]).includes(value);
}
