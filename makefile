_OBJ = dijkstra

make:
	nvcc src/$(_OBJ).cu -o $(_OBJ)