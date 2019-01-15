-- 2 TRIGGER Kiểm soát tính hợp lệ
-- Kiểm tra số lượng sản phẩm còn trong kho có đáp ứng đc nhu cầu order hay không → nhằm thông báo ra để người bán hàng biết mặt hàng đó đã cần nhập thêm hay chưa

DROP TRIGGER IF EXISTS `product_quantity_companent`;
DELIMITER //
CREATE TRIGGER `product_quantity_companent` before INSERT ON `ords_prods`
	FOR EACH ROW
	BEGIN
		DECLARE p_quantity INT;
			SELECT quantity INTO p_quantity  FROM products WHERE id = NEW.product_id;
			IF NEW.quantity > p_quantity OR NEW.quantity < 0 THEN
				SIGNAL SQLSTATE '45000'
				SET MESSAGE_TEXT = 'Currently this product is not enough to supply. Please enter more products into warehouse!';
			END IF;
	END//
DELIMITER ;
INSERT INTO ords_prods VALUES(3,6 ,-10000);
UPDATE products 
SET 
    price = 1000
WHERE
    id = 1;

-- Kiểm tra số lượng số lượng và giá của sản phẩm khi nhập vào bảng product. Cho phép nhập các giá trị hợp lệ lớn hơn 0 còn lại nếu nhỏ hơn 0 sẽ thông báo lỗi → nhằm thông báo ra để người quản lý hàng biết số lượng và giá của sản phẩm mới đó có hợp lệ hay không 
DROP TRIGGER IF EXISTS `BEFORE_NEW_PRODUCTS_INSERT`;
DELIMITER //
	CREATE TRIGGER `BEFORE_NEW_PRODUCTS_INSERT` BEFORE insert ON `products`
	FOR EACH ROW
	BEGIN
		IF NEW.quantity < 0 OR NEW.price < 0 THEN
			SIGNAL SQLSTATE '45000'
			SET MESSAGE_TEXT = 'The quantity or price value is not valid';
		END IF;
	END//
DELIMITER ;
INSERT INTO `products`(pname,price,quantity,category_id) VALUES ('Vở ABC',100,-100,1);

-- 2 INDEX DỮ LIỆU SỐ

CREATE INDEX product_quantity ON products(quantity);
SHOW INDEX FROM products;


CREATE INDEX employee_salary ON employees(salary);
SHOW INDEX FROM employees;

-- 2 INDEX FULL TEXT
-- Kiểm tra những người đã trả hoặc hủy đơn hàng
ALTER TABLE orders ADD FULLTEXT(STATUS);
SELECT * FROM orders WHERE MATCH (STATUS) AGAINST ('Paid' IN NATURAL LANGUAGE MODE);
-- Thống kê các sản phẩm cùng loại hiện đang có trong kho
ALTER TABLE products ADD FULLTEXT(pname);
SELECT * FROM products WHERE MATCH
(pname) AGAINST ('Bút' IN NATURAL LANGUAGE MODE);

-- 2 TRIGGER KIỂM SOÁT SỰ THAY ĐỔI 

-- Trigger update_quantityProd theo dõi sự thay đổi của quantity product(bảng product) khi có 1 hóa đơn mới được thêm vào
DROP TRIGGER IF EXISTS `update_quantityProd`;
DELIMITER //
CREATE TRIGGER `update_quantityProd` BEFORE UPDATE ON `products`
FOR EACH ROW
BEGIN
INSERT INTO product_audit
(id_prod, old_quantity, new_quantity, ACTION,changed_on,message) 
VALUES 
(NEW.id, old.quantity,NEW.quantity, 'update', NOW(),'Quantity change');
END//
DELIMITER ;

DROP TRIGGER IF EXISTS `update_quantityProd1`;
DELIMITER //
CREATE TRIGGER `update_quantityProd1` AFTER INSERT ON `ords_prods`
FOR EACH ROW
BEGIN
	UPDATE `project`.`products` 
    SET `quantity` =  quantity_In_Stock(NEW.order_id, NEW.product_id)
    WHERE (`id` = NEW.product_id);
END//
DELIMITER ;

-- Trigger theo dõi sự thay đổi salary của nhân viên
DROP TRIGGER IF EXISTS `BEFORE_EMPLOYEE_UPDATE_SALARY`;
DELIMITER //
CREATE TRIGGER `BEFORE_EMPLOYEE_UPDATE_SALARY` BEFORE UPDATE ON `employees`
FOR EACH ROW
BEGIN
IF OLD.salary != NEW.salary THEN
INSERT INTO employees_audit
(emp_id, action, changed_on, message) 
VALUES 
(OLD.id,'update', NOW(), CONCAT('The salary was change from', OLD.salary, ' to ', NEW.salary));
END IF;
END//
DELIMITER ;

UPDATE employees SET salary = 8000 WHERE id =1;
SELECT * FROM employees;

-- 2 EVENT

-- Event kiểm tra hàng tồn kho(Kiểm tra 1 tháng 1 lần và kiểm tra từng mặt hàng một.
-- Nếu sản phẩm đó lớn hơn một số lượng nào đó thì thông báo là hàng tồn kho, không cẩn nhập thêm hàng nữa)
DROP EVENT IF EXISTS event_check_inventory; 
Delimiter $$
create event event_check_inventory 
	on schedule at current_timestamp + interval 1 month
	on completion preserve
	enable 
	do
    if products.id = 1 and products.quantity > 8 then
		insert messages(message, create_at)
		VALUE('Hàng đang bị tồn kho, không nhập thêm hàng nữa', now());
    end if;
	$$
Delimiter ;
-- Event thông báo tăng lương nhân viên theo quý và tăng suốt trong quá trình nhân viên đó làm việc. 
-- Tăng lương theo chức vụ của từng nhân viên
DROP event IF EXISTS update_salary;
delimiter $$
create event update_salary
on schedule every 3 month
starts current_timestamp()
on completion preserve 
enable
do 
begin 
insert into messages(message, created_at)
value('The employee is paid periodically!ahihi', now());
SET SQL_SAFE_UPDATES = 0;
update employees set salary = salary + salary*0.5 where title = 'Admin';
update employees set salary = salary + salary*0.2 where title = 'Saler';
update employees set salary = salary + salary*0.4 where title = 'Security';
end;
$$
delimiter ;

-- 2 FUNCTION
-- Tính số lượng quantity sau mỗi lần thay đổi(được dùng trong thân của trigger update_quantityProd).
DELIMITER $$
drop function if exists quantity_In_Stock;
create function quantity_In_Stock(id_order Int, id_product Int) returns int(4) deterministic
begin
	declare result int(4) ;
 	declare quantity_order int(4);
    declare quantity_inStore int(4);
    
	select quantity into quantity_order from ords_prods where order_id = id_order and id_product=product_id ;
    select quantity into quantity_inStore from products where id = id_product ;
    set result = quantity_inStore - quantity_order;
    
    return (result);
End$$
DELIMITER;
select quantity_In_Stock(5,14);

-- Function tính tiền của 1 hóa đơn //sửa lại tên
drop function if exists bill_Payment;
DELIMITER $$
create function bill_Payment(id_order int(4)) returns int(4) deterministic
begin
	declare v_finished int(11) default 0;
	declare v_thanhtien int(11) default 0;
    declare result int(11) default 0;
    
    declare list_cursor cursor for 
    select ords_prods.quantity * products.price
	from products join ords_prods on products.id = ords_prods.product_id 
	where ords_prods.order_id = id_order; 
    
    declare continue handler for not found set v_finished =1;
    set result= 0;
    open list_cursor;
    fetch list_cursor into v_thanhtien;
    
    while v_finished !=1 do 
		 set result= result +v_thanhtien;
         fetch list_cursor into v_thanhtien;
	end while;
    close list_cursor;
    
    return result;
End$$
DELIMITER ;
select bill_Payment (3);

-- 2 VIEW
use project;
-- View kiểm tra thông tin khách hàng bao gồm id,
-- tên khách hàng, địa chỉ, số điểm tích lũy của khách hàng và tổng số đơn hàng đã đặt
select * from kiem_tra_thong_tin_khach_hang;

drop view if exists kiem_tra_thong_tin_khach_hang;
create view kiem_tra_thong_tin_khach_hang as
select customers.id as id_khach_hang, customers.name as ten_khach_hang, customers.address as dia_chi_khach_hang,
customers.loyalty_points as diem_trung_thanh, count(orders.cus_id) as so_luong_don_hang_da_dat 
from customers join orders on customers.id = orders.cus_id group by customers.id;



-- Kiểm tra một hóa đơn bất kỳ
create view checking_the_bill as
select orders.date as thoi_gian, products.pname as ten_san_pham, ords_prods.quantity as so_luong,
products.price as don_gia, ords_prods.quantity * products.price as thanh_tien
from ords_prods 
join products on products.id = ords_prods.product_id 
join orders on ords_prods.order_id = orders.id
where ords_prods.order_id = 2;


-- 2 PROCEDURE

-- Procedure nhập vào hóa đơn thì show ra số tiền, thời gian, các thứ được mua và tổng tiền
//Code
DELIMITER $$
CREATE PROCEDURE check_order(IN id_order INT)
BEGIN
select orders.date as thoi_gian, products.pname as ten_san_pham, ords_prods.quantity as so_luong,
products.price as don_gai, ords_prods.quantity * products.price as thanh_tien
from ords_prods 
join products on products.id = ords_prods.product_id 
join orders on ords_prods.order_id = orders.id
where ords_prods.order_id = id_order;
END$$
DELIMITER ;
call check_order(1);

-- PROCEDURE TRANSACTION 
DELIMITER $$
CREATE PROCEDURE check_order_product(IN id_order INT,in id_ords_prod int)
BEGIN
declare roll_back bool default 0;
declare continue handler for sqlexception set roll_back = 1;
start transaction;
INSERT INTO `orders` VALUES (1,2,1,'2015-07-14 10:00:00','Paid');
INSERT INTO `ords_prods` VALUES (3,1,1),(1,2,4),(2,2,1),(3,3,4);
if roll_back then
rollback;
else 
commit;
end if;
END$$
DELIMITER ;

-- Procedure cập nhật lại điểm tích lũy của khách hàng khi mua hàng
use project;
DROP procedure IF EXISTS `update_loyaltyPoints`;
DELIMITER $$
CREATE procedure `update_loyaltyPoints`(in id_order int,in id_cus int,out point int)  
BEGIN
	declare tongtien int(4) default 0;
	declare tinh_trang_mua_hang varchar(255);
	select status into tinh_trang_mua_hang from orders where id = id_order; 
	set tongtien=bill_Payment(id_order);	
	if(tinh_trang_mua_hang = 'Paid') then
		if(tongtien>=10000) then
				set point = round(tongtien/10000,0);
						   select point; 
				UPDATE `project`.`customers` SET `loyalty_points` = `loyalty_points`+point
				WHERE (`id` = id_cus);
		end if;
	end if;
END$$
DELIMITER ;
call update_loyaltyPoints(1,1,@result);
select @result;