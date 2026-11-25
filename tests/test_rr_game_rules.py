import json
import importlib.util
import tempfile
import unittest
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
from flame_copy import UNIVERSAL_PARAGRAPHS, strip_appended_effect, strip_universal_flame_rules

COMMON = UNIVERSAL_PARAGRAPHS[0]


class GameRulesCopyTests(unittest.TestCase):
    def test_canonical_and_editor_rules_docs_match_and_exist(self):
        canonical = (ROOT / 'docs/game_rules.md').read_text(encoding='utf-8')
        published = (ROOT / 'companion/bullet-editor/game_rules.md').read_text(encoding='utf-8')
        self.assertEqual(canonical, published)
        self.assertIn('【枪口火焰】', canonical)
        self.assertIn('【火焰层数】', canonical)
        self.assertIn('【消耗枪口火焰】', canonical)
        self.assertIn('40.5', canonical)
        self.assertIn('向上燃烧', canonical)
        self.assertIn('实现默认', canonical)
        self.assertIn('最新入库规则', canonical)
        self.assertIn('3×(1+n)', canonical)
        self.assertIn('总伤传递弹', canonical)

    def test_editor_and_readme_link_the_rules_doc(self):
        html = (ROOT / 'companion/bullet-editor/index.html').read_text(encoding='utf-8')
        self.assertIn('href="game_rules.md"', html)
        self.assertIn('游戏规则', html)
        self.assertIn('docs/game_rules.md', (ROOT / 'README.md').read_text(encoding='utf-8'))

    def test_current_copy_has_no_universal_paragraph(self):
        editor = json.loads((ROOT / 'companion/bullet-editor/data.json').read_text())['bullets']
        ammo = json.loads((ROOT / 'data/ammo.json').read_text())['items']
        for row in editor:
            for field in ('effect', 'game_description', 'notes'):
                text = str(row.get(field) or '')
                for para in UNIVERSAL_PARAGRAPHS:
                    self.assertNotIn(para, text, (row['name'], field))
        for row in ammo:
            texts = {
                'special': str(row.get('special') or ''),
                'game_description': str(row.get('game_description') or ''),
                'muzzle_status.effect_description': str((row.get('muzzle_status') or {}).get('effect_description') or ''),
            }
            for field, text in texts.items():
                for para in UNIVERSAL_PARAGRAPHS:
                    self.assertNotIn(para, text, (row['name'], field))

    def test_cleanup_audit_matches_current_values(self):
        report = json.loads((ROOT / 'docs/rr_v0482_description_cleanup.json').read_text())
        self.assertGreaterEqual(len(report['changes']), 20)
        for change in report['changes']:
            doc = json.loads((ROOT / change['file']).read_text())
            rows = doc.get('bullets', doc.get('items'))
            row = next(r for r in rows if r['id'] == change['id'])
            field = change['field']
            cur = row
            for part in field.split('.'):
                cur = (cur or {}).get(part) if isinstance(cur, dict) else None
            # v0.4.85 intentionally revises these unique texts after t658/t666.
            revised = {'倍伤弹','伤害递增弹','叠势弹','尾加倍弹','需要鼓励','模仿弹','重复开始弹','总伤二分弹','传递弹','爆穿'}
            if change['name'] in revised:
                self.assertNotIn(COMMON, cur)
            else:
                self.assertEqual(cur, change['new'], change)

    def test_flavor_and_unique_mechanics_preserved(self):
        editor = {b['name']: b for b in json.loads((ROOT / 'companion/bullet-editor/data.json').read_text())['bullets']}
        self.assertEqual(editor['加伤弹']['game_description'], '给之后的子弹加伤害')
        self.assertIn('×1.5', editor['加伤弹']['effect'])
        self.assertIn('本轮剩余实弹数', editor['加伤弹']['effect'])
        self.assertEqual(editor['倍伤弹']['game_description'], '创造蓄力火焰，只有有伤害的子弹才会消耗它。')
        self.assertIn('【火焰层数】1', editor['倍伤弹']['effect'])
        self.assertIn('+9、+8、+7', editor['传递弹']['effect'])
        self.assertEqual(editor['传递弹']['game_description'], '被加强时会把加强同步给后续子弹')
        zhong = '自身伤害＝本轮此前所有子弹实际造成的总伤害÷2，再应用枪口火焰，最后四舍五入。'
        chuan = (
            '本发经过【枪口火焰】加成并四舍五入后的伤害减去基础伤害3（最低0），即生成的【火焰层数】；每层固定加伤1。'
            '因此超额9后面三发加伤为+9、+8、+7；超额2后面四发为+2、+1、+0、+0，不做总和守恒。'
            '不按穿透命中多个敌人的总伤害计算。'
        )
        bao = '本发经过枪口火焰加成并四舍五入后的伤害大于7时，获得穿透；每穿过一个敌人，伤害减少1，直到伤害耗尽。伤害等于或低于7时不穿透。'
        self.assertEqual(editor['总伤二分弹']['effect'], zhong)
        self.assertEqual(editor['总伤二分弹']['game_description'], '前面越厉害它就越厉害')
        self.assertEqual(editor['传递弹']['effect'], chuan)
        self.assertEqual(editor['爆穿']['effect'], bao)
        self.assertEqual(editor['爆穿']['game_description'], '被加强到极致可以穿透！')
        ammo = {r['name']: r for r in json.loads((ROOT / 'data/ammo.json').read_text())['items']}
        self.assertEqual(ammo['总伤二分弹']['special'], zhong)
        self.assertEqual(ammo['传递弹']['special'], chuan)
        self.assertEqual(ammo['传递弹']['muzzle_status']['effect_description'], chuan)
        self.assertEqual(ammo['爆穿']['special'], bao)
        self.assertNotIn('仍待文案拍板', (ROOT / 'docs/game_rules.md').read_text(encoding='utf-8'))
        self.assertNotIn('表格原文暂未改', (ROOT / 'docs/game_rules.md').read_text(encoding='utf-8'))
        self.assertNotIn('表格原文仍待拍板', (ROOT / 'docs/game_rules.md').read_text(encoding='utf-8'))
        self.assertIn('最后一颗实弹', editor['尾加倍弹']['effect'])
        self.assertIn('发射时消耗全部层', editor['升级引爆']['effect'])
        self.assertIn('【消耗枪口火焰】', editor['升级引爆']['effect'])

    def test_strip_helpers_drop_boilerplate_but_keep_unique_consume_all(self):
        effect = '开火后产生【枪口火焰】，每层伤害×1.5。【火焰层数】1。' + COMMON
        self.assertEqual(strip_universal_flame_rules(effect), '开火后产生【枪口火焰】，每层伤害×1.5。【火焰层数】1。')
        gd = '给之后的子弹加伤害\n' + effect
        self.assertEqual(strip_appended_effect(gd, effect), '给之后的子弹加伤害')
        unique = '【消耗枪口火焰】发射时消耗全部层，每层对所有敌人造成4伤害'
        self.assertEqual(strip_universal_flame_rules(unique), unique)

    def test_sync_stays_idempotent_after_cleanup(self):
        spec = importlib.util.spec_from_file_location('rr_sync', ROOT / 'tools/sync_bullet_editor.py')
        sync = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(sync)
        editor = {b['name']: b for b in json.loads((ROOT / 'companion/bullet-editor/data.json').read_text())['bullets']}
        for row in json.loads((ROOT / 'data/ammo.json').read_text())['items']:
            self.assertEqual(sync.apply_editor_row(dict(row), editor[row['name']]), [], row['name'])

    def test_ingest_strips_boilerplate_instead_of_reappending(self):
        sys.path.insert(0, str(ROOT / '.github/scripts'))
        import bullet_editor_ingest as ingest
        base = Path(tempfile.mkdtemp())
        (base / 'inbox').mkdir()
        doc = json.loads((ROOT / 'companion/bullet-editor/data.json').read_text())
        (base / 'data.json').write_text(json.dumps(doc, ensure_ascii=False), encoding='utf-8')
        payload = {
            'id': 'b20261113-133057-zror',
            'name': '加伤弹',
            'effect': '开火后产生【枪口火焰】，每层伤害×1.5，多层逐层相乘。【火焰层数】本轮剩余实弹数。' + COMMON,
            'game_description': '给之后的子弹加伤害\n开火后产生【枪口火焰】，每层伤害×1.5，多层逐层相乘。【火焰层数】本轮剩余实弹数。' + COMMON,
        }
        merged, failed = ingest.ingest(base, json.dumps(payload, ensure_ascii=False))
        self.assertEqual(failed, [])
        self.assertEqual(merged, ['加伤弹'])
        row = next(b for b in json.loads((base / 'data.json').read_text())['bullets'] if b['id'] == payload['id'])
        self.assertNotIn(COMMON, row['effect'])
        self.assertNotIn(COMMON, row['game_description'])
        self.assertEqual(row['game_description'], '给之后的子弹加伤害')
        self.assertIn('×1.5', row['effect'])


if __name__ == '__main__':
    unittest.main()
