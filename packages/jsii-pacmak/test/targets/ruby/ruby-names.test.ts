import { TypeSystem } from 'jsii-reflect';

import { RubyGenerator } from '../../../lib/targets/ruby';

// The list of acronyms from the CDK (without the fake ones)
const CDK_ACRONYMS = [
  'AWS',
  'CDK',
  'S3',
  'IAM',
  'VPC',
  'SQS',
  'SNS',
  'EC2',
  'RDS',
  'KMS',
  'ECS',
  'EKS',
  'EFS',
  'ELB',
  'WAF',
  'SSM',
  'SES',
  'SAM',
  'MSK',
  'MWAA',
  'ACM',
  'EMR',
  'FSX',
  'QLDB',
  'RAM',
  'FMS',
  'DAX',
  'DMS',
  'DLM',
  'FIS',
  'IVS',
  'CUR',
  'OAM',
  'PCS',
  'RUM',
  'CE',
  'APS',
  'DSQL',
  'ARN',
  'API',
  'DB',
  'CIDR',
  'IP',
  'DNS',
  'URL',
  'URI',
  'SSL',
  'TLS',
  'ALB',
  'NLB',
  'TCP',
  'UDP',
  'IPv4',
];

describe('Ruby naming behavior', () => {
  let typeSystem: TypeSystem;
  let rubyTarget: any; // Use any to access private methods for testing

  beforeAll(async () => {
    typeSystem = new TypeSystem();
    const assembly = await typeSystem.load(
      require.resolve('../fixtures/base.jsii.json'),
    );

    // Mock targets to include the acronyms array
    (assembly as any).spec.targets = {
      ruby: {
        acronyms: CDK_ACRONYMS,
        module: 'BaseModule',
      },
    };

    rubyTarget = new RubyGenerator({
      targetName: 'ruby',
      packageDir: '.',
      assembly,
      runtimeTypeChecking: true,
      arguments: {},
      rosetta: {} as any, // not used for this test
    });
    await rubyTarget.load('.', assembly);
  });

  describe('rubyModuleName', () => {
    it('capitalizes acronyms correctly', () => {
      expect(rubyTarget.rubyModuleName('CfnVpc')).toBe('CfnVPC');
      expect(rubyTarget.rubyModuleName('CfnVPCConnection')).toBe(
        'CfnVPCConnection',
      );
      expect(rubyTarget.rubyModuleName('dbTable')).toBe('DBTable');
      expect(rubyTarget.rubyModuleName('IpAddress')).toBe('IPAddress');
      expect(rubyTarget.rubyModuleName('awsIpv4Cidr')).toBe('AWSIPv4CIDR');
      expect(rubyTarget.rubyModuleName('apiGateway')).toBe('APIGateway'); // API is an acronym
      expect(rubyTarget.rubyModuleName('EcsCluster')).toBe('ECSCluster');
    });

    it('does not over-capitalize acronyms embedded inside words', () => {
      // "Special" contains "pec", "ial" etc. "AWS" is an acronym.
      // "AWSpecial" has "AWS" but it is not followed by an uppercase letter or end of string.
      // With word boundaries, it should remain AWSpecial or Awspecial depending on toPascalCase!
      // In JSII, "AWSpecial" starts with 'A' (uppercase).
      // Our fix ensures it does not get replaced incorrectly.
      expect(rubyTarget.rubyModuleName('AWSpecial')).toBe('AWSpecial');
      expect(rubyTarget.rubyModuleName('VpcEndpoint')).toBe('VPCEndpoint');
      expect(rubyTarget.rubyModuleName('awsCertificatemanager')).toBe(
        'AWSCertificatemanager',
      );
      expect(rubyTarget.rubyModuleName('awsCeService')).toBe('AWSCEService');
    });
  });

  describe('rubyFullTypeName with submodules', () => {
    it('respects explicit submodule targets', () => {
      // Mock an assembly with submodules explicitly configured
      const mockConfig = {
        name: 'aws-cdk-lib',
        targets: { ruby: { module: 'AWSCDK' } },
        submodules: {
          'aws-cdk-lib.aws_dynamodb': {
            targets: { ruby: { module: 'AWSCDK::AWSDynamoDB' } },
          },
          'aws-cdk-lib.aws_dynamodb.nested': {
            targets: { ruby: { module: 'AWSCDK::AWSDynamoDB::Nested' } },
          },
        },
      };

      // Monkey patch this.assembly for the test
      const originalAssembly = rubyTarget.assembly;
      Object.defineProperty(rubyTarget, 'assembly', {
        value: mockConfig,
        configurable: true,
      });

      expect(
        rubyTarget.rubyFullTypeName('aws-cdk-lib.aws_dynamodb.Table'),
      ).toBe('AWSCDK::AWSDynamoDB::Table');

      expect(
        rubyTarget.rubyFullTypeName('aws-cdk-lib.aws_dynamodb.nested.Type'),
      ).toBe('AWSCDK::AWSDynamoDB::Nested::Type');

      // Fallback for unconfigured submodule
      expect(rubyTarget.rubyFullTypeName('aws-cdk-lib.aws_s3.Bucket')).toBe(
        'AWSCDK::AwsS3::Bucket',
      ); // Assuming 'AwsS3' via fallback logic

      Object.defineProperty(rubyTarget, 'assembly', {
        value: originalAssembly,
        configurable: true,
      });
    });
  });
});
