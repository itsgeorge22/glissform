type Key = { label: string; width?: number; kind?: string };
const keys = (labels: string[]): Key[] => labels.map(label => ({ label }));

// ANSI Magic Keyboard proportions: six rows, a full-height function row,
// staggered modifiers, Touch ID and the inverted-T arrow cluster.
const rows: Key[][] = [
  [{ label: 'esc' }, ...keys(Array.from({ length: 12 }, (_, i) => `F${i + 1}`)), { label: '', kind: 'touch-id' }],
  [...keys(['`', '1', '2', '3', '4', '5', '6', '7', '8', '9', '0', '−', '=']), { label: 'delete', width: 1.5 }],
  [{ label: 'tab', width: 1.5 }, ...keys(['Q', 'W', 'E', 'R', 'T', 'Y', 'U', 'I', 'O', 'P', '[', ']', '\\'])],
  [{ label: 'caps lock', width: 1.75 }, ...keys(['A', 'S', 'D', 'F', 'G', 'H', 'J', 'K', 'L', ';', '′']), { label: 'return', width: 1.75 }],
  [{ label: 'shift', width: 2.25 }, ...keys(['Z', 'X', 'C', 'V', 'B', 'N', 'M', ',', '.', '/']), { label: 'shift', width: 2.25 }],
];

function Keycap({ width = 1, kind = '' }: Key) {
  return <span className={`seamless-macbook__key ${kind ? `seamless-macbook__key--${kind}` : ''}`} style={{ flex: width }} />;
}

export default function MacBookKeyboard() {
  return <div className="seamless-macbook__keyboard">
    {rows.map((row, index) => <div className="seamless-macbook__key-row" key={index}>
      {row.map((key, index) => <Keycap {...key} key={index} />)}
    </div>)}
    <div className="seamless-macbook__key-row">
      <Keycap label="fn" /><Keycap label="control" /><Keycap label="option" />
      <Keycap label="⌘" width={1.25} /><Keycap label="" width={5} kind="space" />
      <Keycap label="⌘" width={1.25} /><Keycap label="option" />
      <div className="seamless-macbook__arrows">
        <Keycap label="◀" kind="arrow" />
        <span className="seamless-macbook__arrow-pair"><Keycap label="▲" kind="arrow" /><Keycap label="▼" kind="arrow" /></span>
        <Keycap label="▶" kind="arrow" />
      </div>
    </div>
  </div>;
}
