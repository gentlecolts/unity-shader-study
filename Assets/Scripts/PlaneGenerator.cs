using System.Collections;
using System.Collections.Generic;
using UnityEngine;

[ExecuteInEditMode]
[RequireComponent(typeof(MeshRenderer))]
[RequireComponent(typeof(MeshFilter))]
public class PlaneGenerator : MonoBehaviour
{
	Mesh mesh;
	MeshFilter filter;

	[SerializeField] Vector2 planeSize=new Vector2(1,1);
	[SerializeField] int resolution=1;

	void Awake(){
		mesh=new Mesh();
		filter=GetComponent<MeshFilter>();
		filter.mesh=mesh;
	}

	// Update is called once per frame
	void Update()
	{
		//resolution=Mathf.Clamp(resolution,1,256);

		GeneratePlane(planeSize,resolution);
	}

	void GeneratePlane(Vector2 size,int res){
		var vertices=new List<Vector3>();
		var uvs=new List<Vector2>();
		var normals=new List<Vector3>();

		float xStep=size.x/res;
		float yStep=size.y/res;

		var offset=new Vector3(-size.x/2,0,-size.y/2);
		var uvscale=1.0f/(resolution+1);

		for(int y=0;y<resolution+1;y++){
			for(int x=0;x<resolution+1;x++){
				vertices.Add(new Vector3(x*xStep,0,y*yStep)+offset);
				uvs.Add(new Vector2(x*uvscale,y*uvscale));
				normals.Add(new Vector3(0,1,0));
			}
		}

		var triangles=new List<int>();
		for(int row=0;row<resolution;row++){
			for(int col=0;col<resolution;col++){
				int i=row*(res+1)+col;

				triangles.Add(i);
				triangles.Add(i+res+1);
				triangles.Add(i+res+2);

				triangles.Add(i);
				triangles.Add(i+res+2);
				triangles.Add(i+1);
			}
		}

		mesh.Clear();
		mesh.vertices=vertices.ToArray();
		mesh.triangles=triangles.ToArray();
		mesh.uv=uvs.ToArray();
		mesh.normals=normals.ToArray();
	}
}
