/* dsh-confetti-click — Node half (loader entry plugin).
 *
 * The cordis loader imports every entry's main export and applies it as a
 * plugin, so a client-only package still needs a valid, importable Node
 * half. This one is deliberately empty: all behavior lives in the client
 * bundle (`./client`), discovered by dsh-client-modules through the
 * package.json `dsh.client` declaration.
 */
export const name = "dsh-confetti-click";

export function apply() {
	// Client-only plugin — nothing to do server-side.
}
