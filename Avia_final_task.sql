--1. Выведите название самолетов, которые имеют менее 50 посадочных мест?
select aircraft_code, count(seat_no) as count_seat
from seats
group by aircraft_code
having count(seat_no) < 50

--2.Выведите процентное изменение ежемесячной суммы бронирования билетов, округленной до сотых.
select b_date, ROUND(100.0*((now_sum - previous_sum)/previous_sum), 2) 
from (
	select date_trunc('month', book_date) as b_date, 
		lag(sum(total_amount)) over (order by date_trunc('month', book_date)) as previous_sum,
		sum(total_amount) as now_sum
	from bookings b 
	group by date_trunc('month', book_date)
	order by date_trunc('month', book_date)) t
--формулу исправила, но результат ещё более не корректный не знаю в чем ошибка 

--3.Выведите названия самолетов не имеющих бизнес - класс. Решение должно быть через функцию array_agg.
select aircraft_code, fare_c
from (
	select aircraft_code, array_agg(fare_conditions) as fare_c
	from (
		select aircraft_code, fare_conditions 
		from seats
		order by aircraft_code) t
	group by aircraft_code) d
where 'Business' != all(fare_c)

--4.Вывести накопительный итог количества мест в самолетах по каждому аэропорту на каждый день, 
--учитывая только те самолеты, которые летали пустыми и только те дни, 
--где из одного аэропорта таких самолетов вылетало более одного.
--В результате должны быть код аэропорта, дата, количество пустых мест и накопительный итог.
select departure_airport, actual_departure, amount_free_seats, 
	sum(amount_free_seats) over (partition by departure_airport, actual_departure::date order by date_trunc('day',actual_departure))
from (
	select f.flight_id, f.aircraft_code, 
		b.amount_take_seats, s.amount_free_seats, 
		f.departure_airport, f.actual_departure 
	from flights f
	left join 
		(select flight_id, count(seat_no) as amount_take_seats
		from boarding_passes bp 
		group by flight_id) b on f.flight_id = b.flight_id 
	left join 
		(select aircraft_code, count(seat_no) as amount_free_seats --всего мест в каждом самолете
		from seats 
		group by aircraft_code) s on f.aircraft_code = s.aircraft_code
	where b.amount_take_seats is null
	order by f.actual_departure) t
where actual_departure is not Null
group by actual_departure, departure_airport, amount_free_seats
having count(aircraft_code) > 1 
order by departure_airport

--5.Найдите процентное соотношение перелетов по маршрутам от общего количества перелетов. 
--Выведите в результат названия аэропортов и процентное отношение.
--Решение должно быть через оконную функцию.

/*select a.airport_name, 
	round(count(flight_id) * 100.0 / sum(count(flight_id)) over (), 2)  AS percent_c
from flights f
join airports a on f.departure_airport = a.airport_code  
group by a.airport_name*/

with arrival as (
	select f.flight_id, f.arrival_airport, a.airport_name 
	from flights f
	left join airports a on a.airport_code = f.arrival_airport),
departure as (
	select f.flight_id, f.departure_airport, a.airport_name 
	from flights f
	left join airports a on a.airport_code = f.departure_airport),
fl as (
	select a.flight_id, a.airport_name as arr, d.airport_name as dep
	from departure d
	join arrival a on a.flight_id = d.flight_id)
select fl.dep, fl.arr,
	round(count(fl.flight_id) * 100.0 / sum(count(fl.flight_id)) over (), 2)  AS percent_c
from fl 
group by fl.dep, fl.arr

--6.Выведите количество пассажиров по каждому коду сотового оператора, если учесть, 
--что код оператора - это три символа после +7
select substring((contact_data ->> 'phone')::text from 3 for 3) as tel_operator, count(passenger_id)
from tickets t
group by substring((contact_data ->> 'phone')::text from 3 for 3)

--7.Классифицируйте финансовые обороты (сумма стоимости билетов) по маршрутам:
--До 50 млн - low
--От 50 млн включительно до 150 млн - middle
--От 150 млн включительно - high
--Выведите в результат количество маршрутов в каждом полученном классе.
select c, count(t.departure_airport)
from (
	select f.departure_airport, f.arrival_airport, sum(tf.amount) as sum_amount,
		case 
			when sum(tf.amount) < 50000000 then 'low'
			when sum(tf.amount) >= 50000000 and sum(tf.amount) < 150000000 then 'middle'
			else 'high'
		end	c
	from ticket_flights tf
	join flights f on tf.flight_id = f.flight_id 
	group by f.departure_airport, f.arrival_airport) t
group by c

--8.Вычислите медиану стоимости билетов, медиану размера бронирования 
--и отношение медианы бронирования к медиане стоимости билетов, округленной до сотых.
select med_ticket, med_booking, round((med_booking/med_ticket)::numeric, 2) as attitude
from (
	select percentile_cont(0.5) within group(order by tf.amount) as med_ticket,
		(select percentile_cont(0.5) within group(order by b.total_amount) as med_booking from bookings b)	
	from ticket_flights tf) t
	
--9.Найдите значение минимальной стоимости полета 1 км для пассажиров.
--То есть нужно найти расстояние между аэропортами и с учетом стоимости билетов получить искомый результат.
--Функция earth_distance возвращает результат в метрах.
create extension cube;
create extension earthdistance;
with air as (
	select a.airport_code, ll_to_earth(latitude, longitude) as point1 --координаты аропортов
	from airports a),
fly as (
	select flight_id, flight_no, departure_airport, arrival_airport  -- рейсы
	from flights f),
tic as (
	select flight_id, amount -- билеты и их стоимость 
	from ticket_flights tf),
c_a as (
	select f.flight_id, f.flight_no, f.departure_airport, a.point1 --координаты для аэропорта вылета
	from fly f
	join air a on a.airport_code = f.departure_airport),
c_b as (
	select f.flight_id, f.flight_no, f.arrival_airport, a.point1 --координаты для аэропорта прилета
	from fly f
	join air a on a.airport_code = f.arrival_airport)
select min(am)
from (
	select t.amount / (earth_distance(a.point1, b.point1) / 1000) as am
	from c_a a
	join c_b b on b.flight_id = a.flight_id
	join tic t on a.flight_id = t.flight_id	
	group by a.point1, b.point1, t.amount) g--пробовала здесть убрать группировку, не получилось, не знаю как 	
	
	
	
	