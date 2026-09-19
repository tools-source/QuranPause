"""Generate English and Arabic .strings resources from the reviewed translations."""
import json
from pathlib import Path

root = Path(__file__).resolve().parents[1]
translations = json.loads((root / 'scripts/translations.json').read_text())
for language in ('en', 'ar'):
    path = root / f'QuranTime/Resources/{language}.lproj/Localizable.strings'
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text('\n'.join(
        json.dumps(key, ensure_ascii=False) + ' = ' +
        json.dumps(value if language == 'ar' else key, ensure_ascii=False) + ';'
        for key, value in translations.items()
    ) + '\n')
print(f'Generated {len(translations)} strings for English and Arabic.')
