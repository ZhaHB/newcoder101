/* 查询" 01 "课程比" 02 "课程成绩高的学生的信息及课程分数*/
select * from student right join(
	select table1.SId,course1,course2 from
		(select SId, score as course1 from sc where sc.CId ='01') as table1,
		(select SId, score as course2 from sc where sc.CId ='02') as table2
	where table1.SId = table2.SId and table1.course1 > table2.course2
)r
on student.SId = r.SId


/*查询同时存在" 01 "课程和" 02 "课程的情况*/
select * from
	(select * from sc where sc.CId = '01') as table1,
	(select * from sc where sc.CId = '02') as table2
where table1.SId = table2.SId

/* 查询存在" 01 "课程但可能不存在" 02 "课程的情况(不存在时显示为 null )*/
SELECT * FROM
    (select * from sc WHERE sc.CId = '01') as t1
left join
    (select * from sc where sc.CId = '02') as t2
on t1.SId = t2.SId


/* 查询不存在" 01 "课程但存在" 02 "课程的情况 */
select * from sc
where sc.SId not in (
    select SId from sc
    where sc.CId = '01'
) and sc.CId = '02'


/* 查询平均成绩大于等于 60 分的同学的学生编号和学生姓名和平均成绩 */
select student.SId, sname, ss from student,
    (
    select SId, AVG(score) as ss from sc
    GROUP BY SId
    HAVING AVG(score)>60
    )r
where student.SId = r.SId

/* 查询在 SC 表存在成绩的学生信息 */
select distinct student.*
from student,sc
where student.SId  = sc.SId and sc.score is NOT NULL

/*查询所有同学的学生编号、学生姓名、选课总数、所有课程的成绩总和*/
select student.SId, student.sname, r.sumcourse, r.ccourse from student,(
    select sc.SId, count(sc.CId) as sumcourse, sum(sc.score) as ccourse
    from sc
    GROUP BY sc.SId
)r
where student.SId = r.SId


/* 如要显示没选课的学生(显示为NULL)，需要使用join: */
select s.SId,s.Sname, r.ccount, r.sumscore from(
	(select student.SId, student.Sname 
	from student)s
	left join
	(select sc.SId, count(sc.SId) as ccount, sum(sc.score) as sumscore
	from sc
	group by sc.SId)r
on s.SId = r.SId
);

/* 查有成绩的学生信息 */
select * from student
where EXISTS (
    SELECT sc.SId from sc
    where student.SId = sc.SId
)

/* 查询「李」姓老师的数量 */
select count(teacher.TId) as Tcount
from teacher
where teacher.Tname like '李%'

/* 查询学过「张三」老师授课的同学的信息 多表联合查询 */
select student.* from student,teacher,course,sc
where 
    student.SId = sc.SId and
    sc.CId = course.CId and
    course.TId = teacher.TId and
    teacher.Tname = '张三'

/* 查询没有学全所有课程的同学的信息
    因为有学生什么课都没有选，
    反向思考，
    先查询选了所有课的学生，
    再选择这些人之外的学生. */
select student.* from student
where SId NOT IN (
    select sc.SId from sc
    group by sc.SId
    having count(sc.Cid) = (select count(Cid) from course)
);

/* 查询至少有一门课与学号为" 01 "的同学所学相同的同学的信息 */
select * from student
where SId in(
    select sc.SId from sc
    where sc.CId in(
        select sc.CId from sc
        where sc.SId = '01'
    )
);

/* 查询和" 01 "号的同学学习的课程完全相同的其他同学的信息 */  -- 真的有难度
select * from student
where SId in(
select SId
from sc
where SId<>'01'
group by SId
having group_concat(CId order by CId) = (select group_concat(CId order by CId)
from sc
where sc.SId = '01')
);

