# IAM

Las políticas JSON son plantillas: sustituir REGION, ACCOUNT, nombres de buckets y ARN antes de crearlas. `Resource: *` se usa para operaciones de inventario sin restricción de recurso; afinar con IAM Access Analyzer. El stack 02 crea el rol y perfil de instancia (nombre físico generado por CloudFormation), con RuntimeDataPolicy y las políticas administradas `AmazonSSMManagedInstanceCore` y `CloudWatchAgentServerPolicy`. También concede lectura solo del ZIP de arranque. En Academy, `UsarLabRole=true` reutiliza el perfil suministrado; comprobar sus permisos efectivos.

| Grupo | Políticas recomendadas |
|---|---|
| EcoRAEE-InfraAdmins | EcoRAEE-InfraOpsPolicy |
| EcoRAEE-DBAdmins | DatabaseOpsPolicy |
| EcoRAEE-AppAdmins | AppsOpsPolicy |
| EcoRAEE-Developers | DeveloperPolicy |
| EcoRAEE-Monitoring | AuditReadPolicy |

S3EvidencePolicy se asigna solo a quien opere evidencias; RuntimeDataPolicy al rol, no a usuarios. Estas políticas son conservadoras y no conceden despliegue, cambios de red ni lectura del secreto maestro: conceder mediante rol de despliegue separado y acotado por el administrador. El rol para despliegue necesita además `iam:PassRole` limitado al rol de EC2. El nombre conceptual del rol es EcoRAEE-EC2RuntimeRole; CloudFormation genera su nombre físico para evitar colisiones. No incluir claves de acceso en EC2.
