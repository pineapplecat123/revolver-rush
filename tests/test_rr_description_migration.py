import importlib.util
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]

class DescriptionMigrationTests(unittest.TestCase):
    def test_historical_v0480_audit_is_preserved_as_history(self):
        report = json.loads((ROOT / 'docs/rr_v0480_description_migration.json').read_text())
        self.assertGreater(len(report['changes']), 40)

    def test_editor_sync_cannot_revert_published_copy_or_metadata(self):
        spec = importlib.util.spec_from_file_location('rr_sync', ROOT / 'tools/sync_bullet_editor.py')
        sync = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(sync)
        editor = {b['name']: b for b in json.loads((ROOT / 'companion/bullet-editor/data.json').read_text())['bullets']}
        for row in json.loads((ROOT / 'data/ammo.json').read_text())['items']:
            self.assertEqual(sync.apply_editor_row(dict(row), editor[row['name']]), [], row['name'])

    def test_active_enhancement_effects_keep_specific_terms_not_duration(self):
        ammo = json.loads((ROOT / 'data/ammo.json').read_text())['items']
        for row in ammo:
            if row.get('muzzle_status', {}).get('effect_kind', 'none') == 'none':
                continue
            self.assertIn('【枪口火焰】', row['special'], row['name'])
            self.assertIn('【火焰层数】', row['special'], row['name'])
            self.assertNotIn('【火焰持续时间】', row['special'])
            self.assertNotIn('【火焰持续时间】', row.get('game_description', ''))

if __name__ == '__main__':
    unittest.main()
