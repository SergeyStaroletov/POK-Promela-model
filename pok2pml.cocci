@initialize:python@
@@

map_file2fun = {} 	//file -> function
map_fun2loc = {}	//function -> location
map_fun2syscalls = {}	//function -> line -> syscall with params


class MySyscalls:
    PRINT = 1
    SEM_SIGNAL = 2
    SEM_WAIT = 3
    SLEEP = 4


def correctName(str):
    return str.replace('.c','').replace('..','').replace('/','_')

def findFunByPos(pos, file):
    correct = correctName(file)
    lst_fun = map_file2fun[correct];
    for f in lst_fun:
	(pos_start, pos_end) = map_fun2loc[correct + '_' +f]
	if (pos > pos_start) and (pos < pos_end):
	    return correct +'_'+f
    return ""

def addTuple(fun, pos, tuple):
    pos = int(pos)
    if fun in map_fun2syscalls:
	map = map_fun2syscalls[fun]
	print("adding tuple", fun, tuple, "to pos", pos)
	map[pos] = tuple
	map_fun2syscalls[fun] = map
    else:
	map = {}
	map[pos] = tuple
	print("adding new tuple", fun, tuple, "to pos", pos)
	map_fun2syscalls[fun] = map


//----------------------------
// core top-level rule
//----------------------------
@rule0@ 
identifier ident;
position pf, pe;
@@

(
void * ident@pf () {
...
}@pe
)
* //some functions


//------------------------------
// rules for syscalls
//------------------------------

@print_rule@
expression E;
position pp;
@@
printf(E)@pp

@signal_rule@
identifier sid, i1;
position pp;
@@ 
i1 = pok_sem_signal(sid)@pp

@wait_rule@
identifier sem;
expression wait_value;
position pp;
@@
pok_sem_wait(sem, wait_value)@pp

@sleep_rule@
expression sleep_val;
position pp;
@@
pok_thread_sleep(sleep_val)@pp

//------------------------------
// start of a function
//------------------------------
@script:python depends on rule0@ 
idfun << rule0.ident;
r0p << rule0.pf;
r0end << rule0.pe;
@@
loc = r0p[0].line
loc_end = r0end[0].line
fname = correctName(r0p[0].file)
print("start of function at", idfun, loc, loc_end, 'in', fname)
if fname in map_file2fun:
    lst = map_file2fun[fname]
    lst.append(idfun)
    map_file2fun[fname] = lst
else:
    lst = [idfun]
    map_file2fun[fname] = lst
pos_tuple = (loc, loc_end)
fullname = fname + '_' + idfun;
map_fun2loc[fullname] = pos_tuple


//-----------------------------
// reaction to a particular
// system call - scripts
//-----------------------------
@script:python depends on print_rule@
ee <<  print_rule.E;
pos << print_rule.pp;
@@
fun = findFunByPos(pos[0].line, pos[0].file)
addTuple(fun, pos[0].line, (MySyscalls.PRINT, ee))
print("print on ->", ee, 'at', pos[0].line)

@script:python depends on signal_rule@
ssid << signal_rule.sid;
pos << signal_rule.pp;
@@
fun = findFunByPos(pos[0].line, pos[0].file)
addTuple(fun, pos[0].line, (MySyscalls.SEM_SIGNAL, ssid))
print("sem signal on ->", ssid, 'at', pos[0].line)

@script:python depends on wait_rule@
ssid << wait_rule.sem;
wval << wait_rule.wait_value;
pos << wait_rule.pp;
@@
fun = findFunByPos(pos[0].line, pos[0].file)
addTuple(fun, pos[0].line, (MySyscalls.SEM_WAIT, ssid, wval))
print("sem wait on ->", ssid, 'value', wval, 'at', pos[0].line)

@script:python depends on sleep_rule@
slval << sleep_rule.sleep_val;
pos << sleep_rule.pp;
@@
fun = findFunByPos(pos[0].line, pos[0].file)
addTuple(fun,pos[0].line, (MySyscalls.SLEEP, slval))
print("sleep on ->", slval, 'at', pos[0].line)


//finalize script

@finalize:python@
@@
print("fin!")
print("found functions:")
for key, val in map_file2fun.items():
    print (key, ':')
    for x in val:
	print (x)

print("generated processes:")

for fun in map_fun2loc:
    print("proctype %s(short myPartId; short myThreadId) {" % (fun))
    print("do\n::(osLive == 1) -> \natomic {")
    i = 0
    map = map_fun2syscalls[fun]
    for v in sorted(map.items()):
	//print(v[1])
	print(" if ::(currentPartition == myPartId \n  && currentThread == myThreadId && currentContext.IP == %d) -> \n {" % (i))
	type = v[1][0]
	param = v[1][1]
	if type == MySyscalls.SEM_WAIT:
	    extra = v[1][2]
	if type == MySyscalls.PRINT:
	    print("  pok_print(%s);" % (param.replace(':','').replace(' ','_').replace('\"','').replace('\\n','')))
	elif type == MySyscalls.SEM_SIGNAL:
	    print("  pok_sem_signal(%s, currentContext.r0);" % (param))
	elif type == MySyscalls.SEM_WAIT:
	    print("  pok_sem_wait(%s, %s, currentContext.r0);" % (param, extra))
	elif type == MySyscalls.SLEEP:
	    print("  pok_delay(%s);" % (param))

	print("  currentContext.IP++;\n }")
	print("::else ->")
	i = i + 1
    //adds a loop
    if i > 0: 
	print(" if ::(currentPartition == myPartId \n  && currentThread == myThreadId && currentContext.IP == %d) -> \n {" % (i))
	print("  currentContext.IP = 0;\n }")
	print("::else ->")
    //finalize
    if i > 0: 
	print(" skip");
    for j in range(i + 1, 0, -1):
	sp = ""
        for space in range(j):
	    sp = sp + " "
	print("%sfi" % sp)

    print("}\n::else -> break;\nod")
    print("}\n")


