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

create index product_quantity on products(quantity);
show index from products;


create index employee_salary on employees(salary);
show index from employees;

-- 2 INDEX FULL TEXT

-- Kiểm tra những người đã trả hoặc hủy đơn hàng
alter table orders add fulltext(status);
SELECT * FROM orders WHERE MATCH (status) AGAINST ('Paid' IN NATURAL LANGUAGE MODE);
-- Thống kê các sản phẩm cùng loại hiện đang có trong kho
alter table products add fulltext(pname);
SELECT * FROM products WHERE MATCH
(pname) AGAINST ('Bút' IN NATURAL LANGUAGE MODE);

-- 2 TRIGGER KIỂM SOÁT SỰ THAY ĐỔI 

-- Trigger update_quantityProd theo dõi sự thay đổi của quantity product(bảng product) khi có 1 hóa đơn mới được thêm vào
DROP TRIGGER IF EXISTS `update_quantityProd`;
DELIMITER //
CREATE TRIGGER `update_quantityProd` before update ON `products`
FOR EACH ROW
BEGIN
INSERT INTO product_audit
(id_prod, old_quantity, new_quantity, action,changed_on,message) 
VALUES 
(new.id, old.quantity,new.quantity, 'update', now(),'Quantity change');
END//
DELIMITER ;

DROP TRIGGER IF EXISTS `update_quantityProd1`;
DELIMITER //
CREATE TRIGGER `update_quantityProd1` after insert ON `ords_prods`
FOR EACH ROW
BEGIN
	UPDATE `project`.`products` 
    SET `quantity` =  Calculated_quantity(new.order_id,new.product_id)
    WHERE (`id` = new.product_id);
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

update employees set salary = 8000 where id =1;
select * from employees;

-- 2 EVENT

-- Event kiểm tra hàng tồn kho(Kiểm tra 1 tháng 1 lần và kiểm tra từng mặt hàng một.
-- Nếu sản phẩm đó lớn hơn một số lượng nào đó thì thông báo là hàng tồn kho, không cẩn nhập thêm hàng nữa)
drop event if exists event_check_inventory; 
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
drop function if exists Calculated_quantity;
create function Calculated_quantity(id_order Int, id_product Int) returns int(4) deterministic
begin
	declare result int(4) ;
 	declare quantity_order int(4);
    declare quantity_inStore int(4);
    
	select quantity into quantity_order from ords_prods where order_id = id_order and id_product=product_id ;
    select quantity into quantity_inStore from products where id = id_product ;
    set result = quantity_inStore - quantity_order;
    
    return (result);
End$$
DELIMITER ;
select Calculated_quantity(5,14);

-- Function tính tiền của 1 hóa đơn
drop function if exists Calculated_oder;
DELIMITER $$
create function Calculated_oder(id_order int(4)) returns int(4) deterministic
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
select Calculated_oder (3);

-- 2 VIEW

-- Kiểm tra thông tin người mua hàng nhiều nhất trong một ngày xác định
create view kiem_tra_khach_hang_mua_nhieu_nhat as
select customers.id, customers.name, customers.address from customers join orders on customers.id = orders.cus_id 
where date like '2015-07-18%' and status = 'Paid' having max(cus_id) ;

-- Kiểm tra một hóa đơn bất kỳ
create view checking_the_bill as
select orders.date as thoi_gian, products.pname as ten_san_pham, ords_prods.quantity as so_luong,
products.price as don_gai, ords_prods.quantity * products.price as thanh_tien
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

-- Procedure nhập vào thể loại thì show ra id, name, giá, số lượng, description cho sản phẩm đó
//Code
DELIMITER $$
CREATE PROCEDURE check_product(IN id_category INT)
BEGIN
SELECT id, pname, price, quantity,description
FROM products
WHERE category_id = id_category;
END$$
DELIMITER ;
call check_product(1);





