import importlib.util
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]

class DescriptionMigrationTests(unittest.TestCase):
    def test_audit_matches_every_recorded_current_value(self):
        report = json.loads((ROOT / 'docs/rr_v0480_description_migration.json').read_text())
        self.assertGreater(len(report['changes']), 40)
        for change in report['changes']:
            doc = json.loads((ROOT / change['file']).read_text())
            rows = doc.get('bullets', doc.get('items'))
            row = next(r for r in rows if r['id'] == change['id'])
            self.assertEqual(row.get(change['field']), change['new'], change)

    def test_editor_sync_cannot_revert_published_copy_or_metadata(self):
        spec = importlib.util.spec_from_file_location('rr_sync', ROOT / 'tools/sync_bullet_editor.py')
        sync = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(sync)
        editor = {b['name']: b for b in json.loads((ROOT / 'companion/bullet-editor/data.json').read_text())['bullets']}
        for row in json.loads((ROOT / 'data/ammo.json').read_text())['items']:
            self.assertEqual(sync.apply_editor_row(dict(row), editor[row['name']]), [], row['name'])

    def test_all_active_enhancement_copy_uses_canonical_terms(self):
        ammo = json.loads((ROOT / 'data/ammo.json').read_text())['items']
        for row in ammo:
            if row.get('muzzle_status', {}).get('effect_kind', 'none') == 'none':
                continue
            for field in ['special', 'game_description']:
                self.assertIn('【枪口火焰】', row[field], (row['name'], field))
                self.assertIn('【消耗枪口火焰】', row[field], (row['name'], field))
                self.assertIn('【火焰层数】', row[field], (row['name'], field))
                self.assertNotIn('【火焰持续时间】', row[field])

if __name__ == '__main__':
    unittest.main()
