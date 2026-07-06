# "Quad-Remesher Bridge for Blender"
# Author : Maxime Rouca
#
# ##### BEGIN GPL LICENSE BLOCK #####
#
#  This program is free software; you can redistribute it and/or
#  modify it under the terms of the GNU General Public License
#  as published by the Free Software Foundation; either version 2
#  of the License, or (at your option) any later version.
#
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  You should have received a copy of the GNU General Public License
#  along with this program; if not, see <http://www.gnu.org/licenses/>.
#
# ##### END GPL LICENSE BLOCK #####

import bpy

import os
import subprocess
import sys
import platform
import shutil
import tempfile
import time


def qr_launch_prefix():
    launcher = os.environ.get("QUADREMESHER_LAUNCHER", "").strip()
    return launcher.split() if launcher else []


def writeSettingsFile(settingsFilename, inputFilename, theOp, enableTiming):
    props = bpy.context.scene.qremesher

    settings_file = open(settingsFilename, "w")
    settings_file.write('HostApp=Blender\n')
    settings_file.write('HostAppVer=%s\n' % bpy.app.version_string)
    settings_file.write('FileIn="%s"\n' % inputFilename)
    settings_file.write('FileOut="%s"\n' % theOp.retopoFilename)
    settings_file.write('ProgressFile="%s"\n' % theOp.progressData.ProgressFilename)

    settings_file.write("TargetQuadCount=%s\n" % str(getattr(props, 'target_count')))
    settings_file.write("CurvatureAdaptivness=%s\n" % str(getattr(props, 'adaptive_size')))
    settings_file.write("ExactQuadCount=%d\n" % (not getattr(props, 'adapt_quad_count')))

    settings_file.write("UseVertexColorMap=%s\n" % str(getattr(props, 'use_vertex_color')))
    
    settings_file.write("UseMaterialIds=%d\n" % getattr(props, 'use_materials'))
    settings_file.write("UseIndexedNormals=%d\n" % getattr(props, 'use_normals'))
    settings_file.write("AutoDetectHardEdges=%d\n" % getattr(props, 'autodetect_hard_edges'))

    symAxisText = ''
    if getattr(props, 'symmetry_x') : symAxisText = symAxisText + 'X'
    if getattr(props, 'symmetry_y') : symAxisText = symAxisText + 'Y'
    if getattr(props, 'symmetry_z') : symAxisText = symAxisText + 'Z'
    if symAxisText != '':
        settings_file.write('SymAxis=%s\n' % symAxisText) 
        settings_file.write("SymLocal=1\n")
    
    if enableTiming:
        settings_file.write("Timing_StartRemesh_Time=%f\n" % chrono_startRemeshingTime)
        settings_file.write("Timing_InputMeshExported_Time=%f\n" % time.time()) # this time must include (partially) the txt settings writing.

    settings_file.close()

def exe_launchRemeshing(enginePath, settingsFilename, theOp, verboseDebug):
    if (verboseDebug): 
        print("Launch : path=" + enginePath + "\n    settings_path=" + settingsFilename + "\n")

    theOp.progressData.RemeshingProcess = subprocess.Popen([*qr_launch_prefix(), enginePath, "-s", settingsFilename])

    if (verboseDebug): 
        print("  -> theOp.progressData.RemeshingProcess = " + str(theOp.progressData.RemeshingProcess) + "\n")
    #NB: theOp.progressData.RemeshingProcess.poll()!=None can be done just after subprocess.Popen(...), no need to wait for something... (checked)
