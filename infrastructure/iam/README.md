# IAM de cuenta propia

La fuente desplegable es `../cloudformation/08-iam.yaml`; los JSON de este directorio son el punto de partida histórico, no deben aplicarse por separado. La plantilla agrega las capacidades de operación actuales y sustituye sus marcadores. Las políticas RuntimeDataPolicy y S3EvidencePolicy se usan como referencia para el rol de EC2 creado en 02, no se conceden a usuarios.

| Grupo | Miembros | Administradas por AWS | Propia |
|---|---|---|---|
| EcoRAEE-InfraAdmins | iam-user-infra-nicolas | AWSCloudFormationFullAccess, IAMUserChangePassword | EcoRAEE-InfraOpsPolicy; PassRole exclusivamente a EcoRAEE-CfnDeployRole |
| EcoRAEE-DBAdmins | iam-user-dba-diego | AmazonRDSReadOnlyAccess, IAMUserChangePassword | DatabaseOpsPolicy: lectura del maestro RDS y servicios, inventario y túnel SSM |
| EcoRAEE-AppAdmins | iam-user-app-eithan | AmazonEC2ReadOnlyAccess, IAMUserChangePassword | AppsOpsPolicy: frontend, invalidación y Session Manager |
| EcoRAEE-Developers | iam-user-app-eithan | AWSCloudFormationReadOnlyAccess | DeveloperPolicy: Session Manager |
| EcoRAEE-Monitoring | los tres | CloudWatchReadOnlyAccess, AWSCloudTrail_ReadOnlyAccess | AuditReadPolicy |

Usuarios sin LoginProfile ni claves: el titular crea las credenciales; MFA no se impone en esta plantilla y debe configurarse en la cuenta. El rol EcoRAEE-CfnDeployRole confía en CloudFormation y habilita los servicios usados por 01–07; sus permisos de servicios son amplios y los de IAM se limitan al prefijo, salvo roles vinculados a servicios. No incluye AdministratorAccess. El rol es privilegiado: CloudFormation puede reutilizar un rol ya asociado a un stack. Use cuenta dedicada y refine tras validar con Access Analyzer.

El maestro generado por RDS usa `rds!db-*`, no el prefijo del proyecto: el DBA puede leer secretos maestros RDS de esa región y cuenta; el secreto compuesto se limita al prefijo. Los nombres de frontend y artefactos deben empezar por `${Prefijo}-frontend` y `${Prefijo}-artefactos`. Las distribuciones CloudFront se limitan a la cuenta pero no al proyecto. Las sesiones SSM se limitan a instancias con etiquetas Proyecto y Entorno; el reenvío remoto puede alcanzar cualquier destino accesible desde la instancia. Ver `../README.md` para el orden y las comprobaciones en AWS. Los permisos reales, incluidos los roles vinculados a servicios y LabRole en Academy, requieren validación en la cuenta.
