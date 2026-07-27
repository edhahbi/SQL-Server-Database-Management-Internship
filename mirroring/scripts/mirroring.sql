create master key
    encryption by password = 'ClinisysStage$12';

create certificate MirrorCert 
    with subject = 'Mirroring Certificate [SLAVE]';

backup certificate MirrorCert
    to file = '/var/opt/mssql/certs/MirrorCert.cer';

create certificate PrimaryCert
    from file = '/var/opt/mssql/certs/PrimaryCert.cer';

create login MirrorLogin
    from certificate PrimaryCert;

create endpoint mirroring_endpoint
    state = started
    as tcp (
        listener_port = 5022
        )
    for database_mirroring
        (
        authentication = CERTIFICATE MirrorCert,
        encryption = required algorithm aes ,
        role = partner
        );
go;

grant connect on endpoint::mirroring_endpoint
    to MirrorLogin;

ALTER AVAILABILITY GROUP [AG_Clinisys] JOIN WITH (CLUSTER_TYPE = NONE);
GO

ALTER AVAILABILITY GROUP [AG_Clinisys] GRANT CREATE ANY DATABASE;
GO

SELECT name FROM sys.availability_groups;



