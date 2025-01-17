using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using UnityEditor;
using System.Linq;
using BarkaneEditor;

public class ColorCorrector : MonoBehaviour
{
    public Color Target;
    public Material materialTarget;
}

#if UNITY_EDITOR
[CustomEditor(typeof(ColorCorrector))]
public class GammaCorrectorEditor : Editor
{
    private Color sample;
    private Color adjust;
    private Color tint;

    public override void OnInspectorGUI()
    {
        base.OnInspectorGUI();

        var t = (target as ColorCorrector).Target;
        var mat = (target as ColorCorrector).materialTarget;

        if (GUILayout.Button("Reset to target"))
        {
            mat.SetColor("_Color", t);
            VFXManager.Instance.Refresh<SquareSide>();
        }
        GUILayout.Label("Sample the lightest color on the paper after refresh:");
        sample = EditorGUILayout.ColorField(sample);
        GUILayout.Label($"Error: {t.r - sample.r}, {t.g - sample.g}, {t.b - sample.b}");

        var corr = new Color(t.r * t.r / sample.r, t.g * t.g / sample.g, t.b * t.b / sample.b);
        GUILayout.Label("Corrected: ");
        GUILayout.BeginHorizontal();
        EditorGUILayout.ColorField(corr);
        if (GUILayout.Button("Apply"))
        {
            mat.SetColor("_Color", corr);
            adjust = corr;
            VFXManager.Instance.Refresh<SquareSide>();
        }
        GUILayout.EndHorizontal();

        GUILayout.Label("Adjust base color for finer tuning:");
        GUILayout.BeginHorizontal();
        adjust = EditorGUILayout.ColorField(adjust);
        if (GUILayout.Button("Apply"))
        {
            mat.SetColor("_Color", adjust);
            VFXManager.Instance.Refresh<SquareSide>();
        }

        GUILayout.EndHorizontal();

        GUILayout.Label("Adjust edge tint:");

        GUILayout.BeginHorizontal();
        tint = EditorGUILayout.ColorField(adjust);
        if (GUILayout.Button("Apply"))
        {
            mat.SetColor("_EdgeTint", tint);
            VFXManager.Instance.Refresh<SquareSide>();
        }

        GUILayout.EndHorizontal();
    }
}

#endif