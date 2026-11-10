import pathlib
import unittest

import yaml


ROOT = pathlib.Path(__file__).resolve().parents[1]


class PipelineContractTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = (ROOT / 'azure-pipelines.yml').read_text(encoding='utf-8')
        cls.pipeline = yaml.safe_load(cls.source)

    def test_manual_actions_and_pr_validation(self):
        self.assertEqual(self.pipeline['parameters'][0]['values'], ['validate', 'what-if', 'create'])
        self.assertEqual(self.pipeline['parameters'][0]['default'], 'validate')
        self.assertEqual(self.pipeline['trigger'], 'none')
        self.assertIn('main', self.pipeline['pr']['branches']['include'])

    def test_secret_group_only_in_manual_deploy_stage(self):
        stages = {stage['stage']: stage for stage in self.pipeline['stages']}
        self.assertIn('Validate', stages)
        self.assertIn('Deploy', stages)
        self.assertNotIn('sql-p2s-lab-secrets', str(stages['Validate']))
        self.assertIn('sql-p2s-lab-secrets', str(stages['Deploy']))
        self.assertIn("${{ if ne(parameters.action, 'validate') }}", str(stages['Deploy']['variables']))
        self.assertIn("Build.Reason'], 'Manual'", stages['Deploy']['condition'])
        self.assertIn("Build.SourceBranch'], 'refs/heads/main'", stages['Deploy']['condition'])

    def test_deploy_only_via_named_service_connection(self):
        self.assertIn('sc-sqllab-subscription', self.source)
        self.assertIn('bicep/main.bicep', self.source)
        self.assertIn('bicep/parameters/dev.bicepparam', self.source)
        self.assertIn('az deployment sub what-if', self.source)
        self.assertIn('az deployment sub create', self.source)
        self.assertIn('properties.outputs', self.source)
        self.assertNotIn('set -x', self.source)
        self.assertNotIn('Write-Host $env:SQL_ADMIN_PASSWORD', self.source)


if __name__ == '__main__':
    unittest.main()
