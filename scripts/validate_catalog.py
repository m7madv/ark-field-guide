import json
from pathlib import Path

root = Path(__file__).resolve().parents[1]
rows = json.loads((root / 'Resources/creatures.json').read_text(encoding='utf-8'))
assert rows and len({row['id'] for row in rows}) == len(rows), 'Duplicate or empty IDs'
for row in rows:
    assert set(row) == {'id', 'arabic', 'english', 'aliases', 'assetPath'}
    assert row['arabic'].strip() and any('\u0600' <= char <= '\u06ff' for char in row['arabic'])
    assert row['english'].strip() and isinstance(row['aliases'], list)
    assert all(isinstance(alias, str) and alias.strip() for alias in row['aliases'])
    assert isinstance(row['assetPath'], str) and row['assetPath'].endswith('.uasset')
print(f'Validated {len(rows)} Arabic creature entries')
