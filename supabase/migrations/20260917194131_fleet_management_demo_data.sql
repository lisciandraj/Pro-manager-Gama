alter table public.fleet_vehicles add column is_demo boolean not null default false;
alter table public.fleet_drivers  add column is_demo boolean not null default false;

do $demo$
declare c1 uuid;c2 uuid;c3 uuid;c4 uuid;t1 uuid;t2 uuid;d1 uuid;d2 uuid;d3 uuid;today date:=current_date;
begin
 if exists(select 1 from public.fleet_vehicles) then return;end if;

 insert into public.fleet_drivers(name,phone,licence_number,licence_categories,licence_expiry,is_demo) values
  ('Ana Torres','+593 99 100 2030','EC-1042335','{B}',today+250,true) returning id into d1;
 insert into public.fleet_drivers(name,phone,licence_number,licence_categories,licence_expiry,is_demo) values
  ('Luis Paredes','+593 98 220 4415','EC-2210984','{B,C,E}',today+18,true) returning id into d2;
 insert into public.fleet_drivers(name,phone,licence_number,licence_categories,licence_expiry,is_demo) values
  ('Marta Gil','+593 99 771 6688','EC-3390117','{B,C}',today+540,true) returning id into d3;

 insert into public.fleet_vehicles(plate,brand,model,kind,energy,first_registration,odometer,status,is_demo) values
  ('PCA-1023','Toyota','Corolla','car','hybrid',today-1200,48200,'in_service',true) returning id into c1;
 insert into public.fleet_vehicles(plate,brand,model,kind,energy,first_registration,odometer,status,is_demo) values
  ('PCB-4471','Renault','Clio','car','petrol',today-2100,91500,'in_service',true) returning id into c2;
 insert into public.fleet_vehicles(plate,brand,model,kind,energy,first_registration,odometer,status,is_demo) values
  ('PCC-7788','Peugeot','208','car','diesel',today-900,25400,'repair',true) returning id into c3;
 insert into public.fleet_vehicles(plate,brand,model,kind,energy,first_registration,odometer,status,is_demo) values
  ('PCD-3312','Kia','Niro','car','electric',today-400,12100,'in_service',true) returning id into c4;
 insert into public.fleet_vehicles(plate,brand,model,kind,energy,first_registration,odometer,status,gvwr_kg,payload_kg,is_demo) values
  ('TCA-9001','Mercedes-Benz','Atego 1218','truck','diesel',today-1800,164300,'in_service',12000,6200,true) returning id into t1;
 insert into public.fleet_vehicles(plate,brand,model,kind,energy,first_registration,odometer,status,gvwr_kg,payload_kg,is_demo) values
  ('TCB-2204','Iveco','Daily 35S','truck','diesel',today-700,58700,'in_service',3500,1400,true) returning id into t2;

 insert into public.fleet_assignments(vehicle_id,driver_id,started_on) values
  (c1,d1,today-300),(t1,d2,today-500),(t2,d3,today-120);

 insert into public.fleet_documents(vehicle_id,kind,reference,issued_on,expires_on) values
  (c1,'insurance','POL-88120',today-340,today+25),
  (c1,'technical_inspection','ITV-2026-441',today-200,today+165),
  (c2,'insurance','POL-88121',today-300,today+65),
  (c3,'technical_inspection','ITV-2026-118',today-350,today+12),
  (t1,'insurance','POL-70044',today-360,today+5),
  (t1,'registration','MAT-TCA-9001',today-1800,null),
  (t2,'insurance','POL-70045',today-120,today+245);

 insert into public.fleet_fuel_logs(vehicle_id,driver_id,logged_on,odometer,litres,amount,station) values
  (c1,d1,today-60,46100,38.40,52.30,'Primax Norte'),
  (c1,d1,today-30,47250,41.10,55.80,'Primax Norte'),
  (c1,d1,today-5,48200,36.75,49.90,'Terpel Centro'),
  (c2,null,today-45,89800,45.00,58.50,'Primax Sur'),
  (c2,null,today-10,91500,47.20,61.40,'Primax Sur'),
  (t1,d2,today-40,161200,148.00,196.20,'Estación Ruta 5'),
  (t1,d2,today-8,164300,161.50,214.80,'Estación Ruta 5'),
  (t2,d3,today-20,57100,62.30,82.70,'Terpel Centro'),
  (t2,d3,today-3,58700,58.90,78.10,'Terpel Centro');

 insert into public.fleet_maintenance(vehicle_id,performed_on,odometer,kind,garage,cost,notes,next_service_on,next_service_odometer) values
  (c1,today-75,45200,'service','Taller Andes',180.00,'Revisión de los 45 000 km',today+290,60000),
  (c2,today-25,90100,'tyres','Neumáticos Quito',420.00,'Cuatro neumáticos',null,105000),
  (c3,today-4,25400,'repair','Taller Andes',760.00,'Embrague',null,null),
  (t1,today-50,160000,'service','Taller Pesados',940.00,'Revisión completa',today+20,175000),
  (t2,today-15,56800,'service','Taller Pesados',510.00,'Filtros y aceite',today+165,70000);
end $demo$;
